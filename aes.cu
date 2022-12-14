// AES-128

// AES-128 병렬 컴퓨팅을 이용해서 계산 속도를 올리기.
// 암호화할 블록 크기 : 128bit (평문을 항상 128bit의 배수로 가정할 것이다, 128bit배수가 아니면 비트를 padding시켜야 하는데 병렬 처리가 목적이니 제외했다.)
// 암호화하는 블록당 라운드 수 : 10개
// 라운드 키 크기 : 128bit = 16byte

#include <iostream>
#include <stdlib.h>

#define ROUND 10 
#define STATE_COUNT 1 // 암호화할 블록 갯수 (AES에서 암호화할 128bit를 열 우선 행렬로 변환한 행렬을 STATE라고 한다.)
#define STATE_SIZE 16 // state 크기 16byte
#define KEY_SIZE 16 // 키 크기 16byte
#define CUDA_CHECK(val) { \
    if (val != cudaSuccess) { \
        fprintf(stderr, "Error %s at line %d in file %s\n", cudaGetErrorString(val), __LINE__, __FILE__); \
        exit(1); \
    } \
} // CUDA 관련 함수 호출시 에러가 위치를 명확하게 해주는 함수.

using byte = uint8_t;
using namespace std;
byte* device_sbox;
byte* device_inv_sbox;

const byte sbox[256] = { // SubBytes 모듈에 필요한 테이블
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76,
    0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0,
    0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75,
    0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84,
    0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8,
    0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2,
    0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb,
    0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79,
    0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a,
    0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e,
    0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16 
};

const byte inv_sbox[256] = { // InvSubBytes 모듈에 필요한 테이블
    0x52, 0x09, 0x6a, 0xd5, 0x30, 0x36, 0xa5, 0x38, 0xbf, 0x40, 0xa3, 0x9e, 0x81, 0xf3, 0xd7, 0xfb,
    0x7c, 0xe3, 0x39, 0x82, 0x9b, 0x2f, 0xff, 0x87, 0x34, 0x8e, 0x43, 0x44, 0xc4, 0xde, 0xe9, 0xcb,
    0x54, 0x7b, 0x94, 0x32, 0xa6, 0xc2, 0x23, 0x3d, 0xee, 0x4c, 0x95, 0x0b, 0x42, 0xfa, 0xc3, 0x4e,
    0x08, 0x2e, 0xa1, 0x66, 0x28, 0xd9, 0x24, 0xb2, 0x76, 0x5b, 0xa2, 0x49, 0x6d, 0x8b, 0xd1, 0x25,
    0x72, 0xf8, 0xf6, 0x64, 0x86, 0x68, 0x98, 0x16, 0xd4, 0xa4, 0x5c, 0xcc, 0x5d, 0x65, 0xb6, 0x92,
    0x6c, 0x70, 0x48, 0x50, 0xfd, 0xed, 0xb9, 0xda, 0x5e, 0x15, 0x46, 0x57, 0xa7, 0x8d, 0x9d, 0x84,
    0x90, 0xd8, 0xab, 0x00, 0x8c, 0xbc, 0xd3, 0x0a, 0xf7, 0xe4, 0x58, 0x05, 0xb8, 0xb3, 0x45, 0x06,
    0xd0, 0x2c, 0x1e, 0x8f, 0xca, 0x3f, 0x0f, 0x02, 0xc1, 0xaf, 0xbd, 0x03, 0x01, 0x13, 0x8a, 0x6b,
    0x3a, 0x91, 0x11, 0x41, 0x4f, 0x67, 0xdc, 0xea, 0x97, 0xf2, 0xcf, 0xce, 0xf0, 0xb4, 0xe6, 0x73,
    0x96, 0xac, 0x74, 0x22, 0xe7, 0xad, 0x35, 0x85, 0xe2, 0xf9, 0x37, 0xe8, 0x1c, 0x75, 0xdf, 0x6e,
    0x47, 0xf1, 0x1a, 0x71, 0x1d, 0x29, 0xc5, 0x89, 0x6f, 0xb7, 0x62, 0x0e, 0xaa, 0x18, 0xbe, 0x1b,
    0xfc, 0x56, 0x3e, 0x4b, 0xc6, 0xd2, 0x79, 0x20, 0x9a, 0xdb, 0xc0, 0xfe, 0x78, 0xcd, 0x5a, 0xf4,
    0x1f, 0xdd, 0xa8, 0x33, 0x88, 0x07, 0xc7, 0x31, 0xb1, 0x12, 0x10, 0x59, 0x27, 0x80, 0xec, 0x5f,
    0x60, 0x51, 0x7f, 0xa9, 0x19, 0xb5, 0x4a, 0x0d, 0x2d, 0xe5, 0x7a, 0x9f, 0x93, 0xc9, 0x9c, 0xef,
    0xa0, 0xe0, 0x3b, 0x4d, 0xae, 0x2a, 0xf5, 0xb0, 0xc8, 0xeb, 0xbb, 0x3c, 0x83, 0x53, 0x99, 0x61,
    0x17, 0x2b, 0x04, 0x7e, 0xba, 0x77, 0xd6, 0x26, 0xe1, 0x69, 0x14, 0x63, 0x55, 0x21, 0x0c, 0x7d
};

const byte rcon[11] = { // Round Key 생성 시(Key Expansion) 필요한 테이블
    0xFF, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
};

const byte mix_column_matrix[16] = { // MixColumns 모듈에서 필요한 테이블
    0x02, 0x03, 0x01, 0x01,
    0x01, 0x02, 0x03, 0x01,
    0x01, 0x01, 0x02, 0x03,
    0x03, 0x01, 0x01, 0x02
};

const byte inv_mix_column_matrix[16] = { // InvMixColumns 모듈에서 필요한 테이블 (역행렬)
    0x0E, 0x0B, 0x0D, 0x09,
    0x09, 0x0E, 0x0B, 0x0D,
    0x0D, 0x09, 0x0E, 0x0B,
    0x0B, 0x0D, 0x09, 0x0E
};

__global__ void AddRoundKey(byte* plaintext, byte* key, int round){
    int idx = (blockDim.x * blockDim.y) * blockIdx.x + threadIdx.y * blockDim.y + threadIdx.x;
    byte ret = plaintext[idx] ^ key[round * 16 + idx];   
    plaintext[idx] = ret;
}

__global__ void SubBytes(byte* plaintext, byte* sbox){
    int idx = (blockDim.x * blockDim.y) * blockIdx.x + threadIdx.y * blockDim.y + threadIdx.x;
    byte ret = sbox[plaintext[idx]];
    plaintext[idx] = ret;
}

__global__ void ShiftRows(byte* plaintext, bool inverse){ // inverse가 True이면 InvShiftRow 모듈이 된다.
    int idx = (blockDim.x * blockDim.y) * blockIdx.x + threadIdx.y * blockDim.y + threadIdx.x;
    int value = plaintext[idx];
    int shift_y;
    if(inverse) shift_y = (threadIdx.y - threadIdx.x) % 4; // left shift
    else shift_y = (threadIdx.y + threadIdx.x) % 4; // right shift

    int idx2 = (blockDim.x * blockDim.y) * blockIdx.x + shift_y * blockDim.y + threadIdx.x;
    plaintext[idx2] = value;
}

__device__ byte GaloisCalc(byte b, int n){ // 갈루아체, GF(2^8)에서 x^n과 연산
    if(n == 1) return b;
    return GaloisCalc(b * 2 ^ (b & 0x80 ? 0x1B : 0x00), n - 1); // 곱연산시 2^8이 넘어가면 0x1B와 xor을 하여 overflow 방지
}

__global__ void MixColumns(byte* plaintext, byte* mix_column_matrix){
    int idx = (blockDim.x * blockDim.y) * blockIdx.x + threadIdx.y * blockDim.y + threadIdx.x;
    byte ret = 0x00;
    for(int i = 0;i < 4;i++){ // 갈루아체에서 다항식 행 곱셈
        byte b1 = mix_column_matrix[threadIdx.x * blockDim.x + i];
        int idx2 = (blockDim.x * blockDim.y) * blockIdx.x + threadIdx.y * blockDim.y + i;
        byte b2 = plaintext[idx2];
        if(b1 == 0x01) ret ^= GaloisCalc(b2, 1);
        else if(b1 == 0x02) ret ^= GaloisCalc(b2, 2);
        else if(b1 == 0x03){
            ret ^= GaloisCalc(b2, 2);
            ret ^= GaloisCalc(b2, 1);
        }else if(b1 == 0x09){
            ret ^= GaloisCalc(b2, 4);
            ret ^= GaloisCalc(b2, 1);
        }else if(b1 == 0x0B){
            ret ^= GaloisCalc(b2, 4);
            ret ^= GaloisCalc(b2, 2);
            ret ^= GaloisCalc(b2, 1);
        }else if(b1 == 0x0D){
            ret ^= GaloisCalc(b2, 4);
            ret ^= GaloisCalc(b2, 3);
            ret ^= GaloisCalc(b2, 1);
        }else if(b1 == 0x0E){
            ret ^= GaloisCalc(b2, 4);
            ret ^= GaloisCalc(b2, 3);
            ret ^= GaloisCalc(b2, 2);
        }
    }
    // __syncthreads();
    plaintext[idx] = ret;
}

// 라운드마다 적용할 키 생성
void KeyExpansion(byte* key){
    for(int i = 1;i < ROUND + 1;i++){
        int j = i * 16;
        byte b[4] = {key[j - 1] , key[j - 2], key[j - 3], key[j - 4]};
        byte tmp = b[0];
        // rotation 1byte
        for(int k = 0;k < 3;k++) {
            b[k] = b[k + 1];
        }
        b[3] = tmp;
        
        for(int k = 0;k < 4;k++) b[k] = sbox[b[k]];
        b[0] = b[0] ^ rcon[i];

        key[j] = key[j - 16] ^ b[0];
        key[j + 1] = key[j - 15] ^ b[1];
        key[j + 2] = key[j - 14] ^ b[2];
        key[j + 3] = key[j - 13] ^ b[3];
        for(int k = 4;k < 16;k++) key[j + k] = key[j + k -16 - 4] ^ key[j + k - 4];
    }
}

int main(){
    byte* plaintext;
    byte* key;

    plaintext = (byte *) malloc(sizeof(byte) * STATE_SIZE * STATE_COUNT);
    key = (byte *) malloc(sizeof(byte) * KEY_SIZE * (ROUND + 1));
    
    // key 생성
    for(int i = 0;i < KEY_SIZE;i++){
        byte b = (byte) (rand() % 256);
        key[i] = b;
    }

    // 암호화할 평문 생성
    for(int i = 0;i < STATE_COUNT;i++){
        for(int j = 0;j < STATE_SIZE;j++){
            byte b = (byte) (rand() % 256);
            plaintext[i * 16 + j] = b;
        }
    }

    printf("----------평문\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");
    
    byte* device_plaintext;
    byte* device_round_key;
    byte* device_mix_column_matrix;
    byte* device_inv_mix_column_matrix;

    CUDA_CHECK(cudaMalloc((void **) &device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT));
    CUDA_CHECK(cudaMalloc((void **) &device_round_key, sizeof(byte) * KEY_SIZE * (ROUND + 1)));
    CUDA_CHECK(cudaMalloc((void **) &device_sbox, sizeof(byte) * 256));
    CUDA_CHECK(cudaMalloc((void **) &device_inv_sbox, sizeof(byte) * 256));
    CUDA_CHECK(cudaMalloc((void **) &device_mix_column_matrix, sizeof(byte) * 16));
    CUDA_CHECK(cudaMalloc((void **) &device_inv_mix_column_matrix, sizeof(byte) * 16));

    KeyExpansion(key); // 라운드 키를 만든다.

    CUDA_CHECK(cudaMemcpy(device_round_key, key, sizeof(byte) * KEY_SIZE * (ROUND + 1), cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_plaintext, plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_sbox, sbox, sizeof(byte) * 256, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_inv_sbox, inv_sbox, sizeof(byte) * 256, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_mix_column_matrix, mix_column_matrix, sizeof(byte) * 16, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(device_inv_mix_column_matrix, inv_mix_column_matrix, sizeof(byte) * 16, cudaMemcpyHostToDevice));

    dim3 dimBlock(4, 4, 1); // Block당 스레드 수 (4 x 4 = 16개)
    
    // 암호화
    AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, 0);
    CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
    printf("----------pre-round transformation 암호화 결과\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");
    for(int i = 1;i < ROUND;i++){
        SubBytes<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_sbox);
        ShiftRows<<<STATE_COUNT, dimBlock>>>(device_plaintext, false);
        MixColumns<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_mix_column_matrix);    
        AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, i);
        CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
        printf("----------round %d 암호화 결과\n\n", i);
        for(int j = 0;j < STATE_SIZE * STATE_COUNT;j++){
            printf("%#04x ", plaintext[j]);
        }
        printf("\n\n");
    }

    SubBytes<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_sbox);
    ShiftRows<<<STATE_COUNT, dimBlock>>>(device_plaintext, false);
    AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, ROUND); // 마지막 암호화는 MixColumns 제외
    
    // 암호화 결과
    CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
    printf("----------round 10 암호화 결과\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");

    // 복호화
    AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, ROUND);
    ShiftRows<<<STATE_COUNT, dimBlock>>>(device_plaintext, true);
    SubBytes<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_inv_sbox);
    CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
    printf("----------round 10 복호화 결과\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");
    for(int i = ROUND - 1;i > 0;i--){
        AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, i);
        MixColumns<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_inv_mix_column_matrix);
        ShiftRows<<<STATE_COUNT, dimBlock>>>(device_plaintext, true);
        SubBytes<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_inv_sbox);
        CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
        printf("----------round %d 복호화 결과\n\n", i);
        for(int j = 0;j < STATE_SIZE * STATE_COUNT;j++){
            printf("%#04x ", plaintext[j]);
        }
        printf("\n\n");
    }
    AddRoundKey<<<STATE_COUNT, dimBlock>>>(device_plaintext, device_round_key, 0);
    CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
    printf("----------pre-round transformation 복호화 결과\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");

    // 복호화 결과
    CUDA_CHECK(cudaMemcpy(plaintext, device_plaintext, sizeof(byte) * STATE_SIZE * STATE_COUNT, cudaMemcpyDeviceToHost));
    printf("----------복호화 결과\n\n");
    for(int i = 0;i < STATE_SIZE * STATE_COUNT;i++){
        printf("%#04x ", plaintext[i]);
    }
    printf("\n\n");
    
    CUDA_CHECK(cudaFree(device_plaintext));
    CUDA_CHECK(cudaFree(device_round_key));
    CUDA_CHECK(cudaFree(device_sbox));
    CUDA_CHECK(cudaFree(device_inv_sbox));
    CUDA_CHECK(cudaFree(device_mix_column_matrix));
    CUDA_CHECK(cudaFree(device_inv_mix_column_matrix));

    free(plaintext);
    free(key);

    return 0;
}
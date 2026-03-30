- Input data block: 128 bit
- Input key: 256 bit
- mode: ECB
- KeyExpansion generates 15 round keys (rk0...rk14), each 128 bit
- Datapath has 15 pipeline stages:
  + Stage 0: initial AddRoundKey
  + Stage 1..13: full AES rounds
    (SubBytes -> ShiftRows -> MixColumns -> AddRoundKey)
  + Stage 14: final AES round
    (SubBytes -> ShiftRows -> AddRoundKey)
- Each pipeline stage consists of combinational round logic and one register
- Data moves one stage per clock
- valid_pipe is used to track which stage contains valid data
- After pipeline is filled, throughput = 1 block per clock
- Ciphertext output is valid when valid_out = 1

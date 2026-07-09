# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import binascii
import random
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge

RESIDUE = 0x2144DF1C
CLK_PERIOD_NS = 8

async def start_clock_and_reset(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, "ns").start())
    dut.i_valid.value = 0
    dut.i_last.value = 0
    dut.i_corrupt.value = 0
    dut.i_8xframe.value = 0
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 4)
    dut.rstn.value = 1
    await RisingEdge(dut.clk)

async def send_frame(dut, data: bytes, corrupt_on_beat: int = -1):
    assert len(data) % 8 == 0 and len(data) > 0
    beats = [data[i:i+8] for i in range(0, len(data), 8)]
    for i, chunk in enumerate(beats):
        dut.i_8xframe.value = int.from_bytes(chunk, "little")
        dut.i_valid.value = 1
        dut.i_last.value = 1 if i ==len(beats) - 1 else 0
        dut.i_corrupt.value = 1 if i == corrupt_on_beat else 0
        await RisingEdge(dut.clk)
    dut.i_valid.value = 0
    dut.i_last.value = 0
    dut.i_corrupt.value = 0

async def read_result(dut) -> int:
    await ClockCycles(dut.clk, 2)
    return int(dut.o_crc.value)

def golden(data: bytes) -> int:
    return binascii.crc32(data) & 0xFFFFFFFF


@cocotb.test()
async def test_known_vectors(dut):
    await start_clock_and_reset(dut)
    for frame in (bytes(range(1,9)), b"ABCDEFGHIJKLMNOP"):
        await send_frame(dut, frame)
        got = await read_result(dut)
        exp = golden(frame)
        assert got ==exp, f"frame {frame.hex()}: got {got:08X}, expected {exp:08X}"

@cocotb.test()
async def test_residue_property(dut):
    await start_clock_and_reset(dut)
    data = b"Hello, World"
    fcs = golden(data).to_bytes(4, "little")
    await send_frame(dut, data + fcs)
    got = await read_result(dut)
    assert got == RESIDUE, f"residue: got {got:08X}, expected {RESIDUE:08X}"

@cocotb.test()
async def test_back_to_back_frames(dut):
    await start_clock_and_reset(dut)
    f1, f2 = bytes(range(1, 9)), b"ABCDEFGHIJKLMNOP"
    await send_frame(dut, f1)
    await send_frame(dut, f2)
    got = await read_result(dut)
    exp = golden(f2)
    assert got == exp, f"back to back: got {got:08X}, expected {exp:08X}"

@cocotb.test()
async def test_corrupt_injection(dut):
    await start_clock_and_reset(dut)
    frame = b"ABCDEFGHIJKLMNOP"
    await send_frame(dut, frame, corrupt_on_beat = 0)
    got = await read_result(dut)
    exp = golden(frame) ^ 0x1
    assert got == exp, f"corrupt: got {got:08X}, expected {exp:08X}"
    await send_frame(dut, frame)
    got = await read_result(dut)
    assert got == golden(frame), "corruption leaked into the frame"

@cocotb.test()
async def test_reset_mid_frame(dut):
    await start_clock_and_reset(dut)
    dut.i_8xframe.value = 0xDEADBEEF_DEADBEEF
    dut.i_valid.value = 1
    dut.i_last.value = 0
    await RisingEdge(dut.clk)
    dut.i_valid.value = 0
    dut.rstn.value = 0
    await ClockCycles(dut.clk, 2)
    dut.rstn.value = 1
    await RisingEdge(dut.clk)
    frame = bytes(range(1,9))
    await send_frame(dut,frame)
    got = await read_result(dut)
    exp = golden(frame)
    assert got == exp, f"post reset: got {got:08X}, expected {exp:08X}"

@cocotb.test()
async def test_random_frames(dut):
    await start_clock_and_reset(dut)
    rng = random.Random(1234)
    for _ in range(200):
        frame = rng.randbytes(8 * rng.randint(1, 32))
        await send_frame(dut,frame)
        got = await read_result(dut)
        exp = golden(frame)
        assert got == exp, f"random frame len={len(frame)}: got {got:08X}, expected {exp:08X}"
        await ClockCycles(dut.clk, rng.randint(0, 3))

                        
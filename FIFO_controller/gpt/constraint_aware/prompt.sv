Generate synthesizable SystemVerilog RTL for a parameterized synchronous FIFO controller following these exact instructions:

Features required: full, empty, almost_full, almost_empty flags, fifo_count output, overflow_flag, underflow_flag, simultaneous read/write support.

Hardware/design constraints:
- Target FPGA: AMD/Xilinx Artix-7
- Tool: Vivado 2025.2
- Must be synthesizable SystemVerilog
- Parameterized with DATA_WIDTH, DEPTH (power of 2, enforced via a generate-time assumption/assertion), ALMOST_FULL_THRESHOLD, ALMOST_EMPTY_THRESHOLD
- Must use synchronous reset (active-high, on clk posedge)
- Must NOT infer any latches (every case/if in combinational logic must have a default assignment)
- Memory array must be coded in a style that allows Vivado to infer Block RAM (BRAM) for DEPTH >= 16; use a registered read-data output (synchronous read) rather than combinational read, to match BRAM output-register behavior
- Use $clog2(DEPTH) for all pointer and count widths; avoid width mismatches
- fifo_count must be maintained by a dedicated up/down counter (not derived every cycle by subtracting pointers, to minimize combinational logic depth)
- Minimize LUT and flip-flop usage; avoid unnecessary registers
- Target maximum operating frequency: 100 MHz
- Clearly separate: pointer/count registers, memory instantiation, flag generation logic, and read/write control logic
- overflow_flag and underflow_flag must be registered, single-cycle pulses indicating an invalid write/read was attempted and blocked
- wr_en while full must be silently blocked (no memory write, no pointer increment) and must assert overflow_flag; rd_en while empty must be silently blocked and must assert underflow_flag

Provide the complete RTL code only, followed by a brief explanation of how the design achieves BRAM inference and timing closure at 100 MHz.

SWD · RISC-V [Why](#why) [What your core needs](#needs) [What this supplies](#supplies) [Status](#status) [Evaluate](#evaluate)

Proposal · Open two-wire debug for RISC-V soft cores

# Debug a RISC-V core over two pins.

An Arm Serial Wire Debug front-end for VexRiscv and VexiiRiscv, merged upstream and driving the same RISC-V DebugBus the JTAG DTM already uses. The Debug Module and the CPU are unchanged.

Funded by NLnet NGI0 Commons Fund · grant 2025-02-159

SWD write transaction, as the target sees it

**1**Start

**A**APnDP

**W**RnW

**A2**addr

**A3**addr

**P**parity

**0**Stop

**1**Park

**→**Trn

**ACK**3 bits

**←**Trn

**DATA\[31:0\]**LSB first

**P**parity

host drives SWDIO target drives SWDIO turnaround SWCLK supplied by the probe

Pins2 versus 4 to 5

UpstreamSpinalHDL, VexRiscv, VexiiRiscv, LiteX

Validated onArtix-7, GDB over CMSIS-DAP

SiliconNot yet taped out

<a id="why"></a>

01 · Why this exists

## The ratified debug specification defines only a JTAG transport.

JTAG needs TCK, TMS, TDI and TDO, plus TRST where a reset line is wanted. Serial Wire Debug needs SWCLK and SWDIO. On a pin-constrained ASIC or a small FPGA board those two or three pins are contested, and on-chip debug is usually what gets cut.

Adding SWD to the RISC-V Debug Specification was requested and never adopted, so Raspberry Pi shipped it as a custom Debug Transport Module, which the specification explicitly permits. This project takes the same route for the VexRiscv family, in the open, under the upstream licences.

Stated precisely

This implements the RISC-V Debug Specification with a custom SWD transport. It is not an unqualified conformance claim, because no ratified version of the specification defines an SWD DTM. Describe it that way in any brief or datasheet.

[riscv-debug-spec issue #785](https://github.com/riscv/riscv-debug-spec/issues/785) tracks the original request.

02 · At a glance

### What changes

A new transport front-end: wire-level PHY, SW-DP register file, and a DMI gateway with clock-domain crossing. Two pads instead of four or five.

### What does not change

The Debug Module and the hart. Both are transport-agnostic in the specification, so a core that already has spec-compliant debug needs no redesign.

### What you get back

Stock GDB behaviour. Halt, examine registers and memory, set breakpoints, single-step, load code, all over an off-the-shelf CMSIS-DAP probe.

<a id="needs"></a>

03 · Requirements

## What a RISC-V processor needs to implement a debug interface.

Seven layers. Layers 2 and 3 are transport-agnostic, which is the reason adding SWD meant writing a front-end rather than touching the core.

01

### Debug Transport Module

Converts a wire protocol into Debug Module Interface reads and writes. The specification defines a JTAG DTM with `IDCODE`, `dtmcs` and `dmi` registers, and permits custom transports.

| Element | Need | Note |
| --- | --- | --- |
| DMI master | required | Address, data, read/write op, busy status for backpressure |
| Clock-domain crossing | required | The probe clock is asynchronous and intermittent. It stops when the probe idles, so the CDC cannot assume a free-running clock |
| Error and retry semantics | required | The host must distinguish "busy, retry" from "failed" |

02

### Debug Module

A DMI slave holding the debug register file. Without at least one of a Program Buffer or System Bus Access, a debugger can read registers but not memory.

| Element | Need | Note |
| --- | --- | --- |
| `dmcontrol` | required | dmactive, haltreq, resumereq, ndmreset, hartsel |
| `dmstatus` | required | allhalted, anyhalted, allrunning, allresumeack, authenticated |
| `hartinfo`, `abstractcs`, `command`, `data0..N` | required | Abstract command interface and its data registers |
| Access Register command | required | Minimum viable command set: GPR and CSR read and write |
| Program Buffer `progbuf` | one of two | Feeds instructions to the halted hart; the usual route to memory access |
| System Bus Access | one of two | sbcs, sbaddress, sbdata. Bus master that reaches memory without halting |
| `abstractauto` | optional | Autoexec on data access. The difference between tolerable and glacial block download |
| Authentication `authdata` | optional | Needed on production parts; see layer 06 |

03

### The hart

The layer most often underestimated. Debug Mode is a distinct operating mode above M-mode, with its own entry paths, register set and exit instruction.

| Element | Need | Note |
| --- | --- | --- |
| Debug Mode | required | Operating mode above M-mode |
| `dcsr`, `dpc` | required | Debug control and status, saved PC |
| `dscratch0`, `dscratch1` | with progbuf | Scratch for program-buffer execution |
| Halt entry paths | required | haltreq, `ebreak`, trigger fire, step completion, halt-on-reset |
| Park loop | required | A debug address region the hart enters on halt, where it spins and executes abstract commands |
| Redefined `ebreak` | required | In Debug Mode it returns to the park loop instead of trapping |
| `dret` | required | Exit from Debug Mode |
| step, stopcount, stoptime | required | Single-step, and freezing counters and timers while halted |

04

### Trigger Module

Optional in the specification. Without it there are no hardware breakpoints, which means no breakpoints in ROM or flash and no watchpoints. Each trigger costs comparator area, which is why implementations ship two to four rather than sixteen.

| Element | Need | Note |
| --- | --- | --- |
| `tselect`, `tdata1..3`, `tinfo` | optional | Trigger register interface |
| Address or data match trigger | optional | mcontrol class. The minimum for a usable hardware breakpoint |

05

### Reset

| Element | Need | Note |
| --- | --- | --- |
| ndmreset | required | Resets the system but not the Debug Module |
| hartreset | optional | Per-hart reset |
| Halt-on-reset resethaltreq | in practice required | The only way to debug from the first instruction. Frequently omitted, then missed during boot bring-up |
| Transport reset | required | SWD has no reset wire. Recovery is the line-reset sequence on SWDIO: at least 50 clocks high, then idle cycles |

06

### What the SoC integrator must provide

The layer where SWD diverges from JTAG, and the one to settle before committing to a hardened flow.

| Element | Need | Note |
| --- | --- | --- |
| Two pins | required | SWCLK and SWDIO |
| Bidirectional pad for SWDIO | required | Output enable switchable per cycle. The protocol turns the line around inside one clock period |
| Input pad that can clock logic | required | SWCLK is externally driven and must reach sequential logic as a clock. The hardest constraint in a fixed harness |
| Live from power-up | required | A debug port that firmware has to enable cannot debug why the firmware did not run |
| Access control | production | Two exposed pins give full register and memory access. Either DM authentication or a fuse or lifecycle lock |

07

### Host side

| Element | Need | Note |
| --- | --- | --- |
| OpenOCD with a `riscv` target | required | Plus a target config describing the DTM and work area |
| GDB remote serial protocol | required | Standard client, no patches |
| A probe speaking the transport | required | CMSIS-DAP for SWD. Validated here with MCU-Link and Black Magic Probe |

<a id="supplies"></a>

04 · Division of labour

## What this project supplies, and what you already have.

| Layer | Supplied by | Detail |
| --- | --- | --- |
| 01 Transport (DTM) | this project | SwdPhy, SwdDp register file, DMI gateway with clock crossing |
| 02 Debug Module | unchanged | Existing VexRiscv Debug Module, reached over the same DebugBus |
| 03 Hart support | unchanged | Debug Mode, debug CSRs and park loop already in the core |
| 04 Triggers | unchanged | Whatever the core configuration already provides |
| 05 Reset | partly this project | SWDIO line-reset handling in the transport; system reset unchanged |
| 06 SoC integration | this project | LiteX `--with-swd-debug` brings SWDIO out to SoC pins; ElemRV integration merged |
| 07 Host side | partly, see caveat | OpenOCD gateway and Black Magic Probe support |

Open caveat

Upstream OpenOCD does not support a RISC-V target behind an Arm SW-DP. Stock OpenOCD reaches raw-AP; the full RISC-V and GDB path currently needs a fork, as it does for Raspberry Pi. Whether this can be upstreamed rather than carried downstream is an open question and a good reason to talk if you build debug tooling.

<a id="status"></a>

05 · Status

## Merged upstream, running on FPGA, not yet in silicon.

| Area | Result | Upstream |
| --- | --- | --- |
| Core SWD implementation | SWD DTM wired end to end, verified in simulation | SpinalHDL #1956, #1966 |
| VexRiscv | SWD interface in the core and derivatives | #483, #499, #500 |
| VexiiRiscv | Same interface in the newer core family | #184, #188 |
| LiteX SoC integration | `--with-cpu-jtag-debug` and `--with-swd-debug`; three-wire SWDIO to SoC pins | LiteX #2572, #2669; linux-on-litex-vexriscv #459 |
| Commercial SoC | SWDIO exposed on ElemRV | elements-nafarr #72, elements-zibal #62 |
| Host tooling | Raw-AP on stock OpenOCD; full RISC-V and GDB on a fork; Black Magic Probe support | openocd/vexriscv-gateway; Black Magic #2322 |
| Hardware | Digilent Arty, MCU-Link CMSIS-DAP probe on a Pmod header. OpenOCD examine, GDB load, break and stepi. JTAG through BSCANE2 for comparison | — |

Remaining work is the full regression matrix and documentation. Silicon validation on an open process is the next step and is not yet funded.

<a id="evaluate"></a>

06 · Evaluation

## What an evaluation looks like.

The fastest route for a board or SoC team is a LiteX build, because two-wire debug is one flag away.

- Build a LiteX SoC with `--with-swd-debug` for your target board.
- Wire SWCLK and SWDIO to a CMSIS-DAP probe. Two signals and a ground.
- Run OpenOCD with the supplied target config, then attach GDB.
- Expect examine to pass, then `load`, a breakpoint, and `stepi` to behave as they do over JTAG.

A paid integration for one specific core, board and probe combination is available, with named software revisions, an agreed set of debug operations, acceptance tests, and a separate maintenance arrangement. The RTL stays open under its upstream licences either way.

07 · Questions engineers ask

### Is this standards-compliant RISC-V debug?

It implements the RISC-V Debug Specification with a custom SWD transport. The Debug Module and hart behaviour are per specification. The transport is not, because no ratified version of the specification defines an SWD DTM.

### Do I have to change my core?

No, if it already has a spec-compliant Debug Module and hart-side debug support. Those layers are transport-agnostic. You add a front-end and two pads.

### Why not just use JTAG?

Use JTAG if you have the pins. SWD matters when you do not: two signals instead of four or five, on parts where the pin budget is what forced debug off the chip in the first place.

### Which probes work?

Any CMSIS-DAP probe. Validated with an NXP MCU-Link and with Black Magic Probe, whose firmware now carries support for this path.

### Does stock OpenOCD work?

For raw-AP access, yes. For the full RISC-V target with GDB, not yet. That path needs the fork, which is the same position Raspberry Pi is in.

### Has it run in silicon?

Not yet. Everything above is simulation and FPGA, on a Digilent Arty with a real probe. Silicon validation is the open item, and the honest answer to give an adopter.

### What does it cost in area?

The transport front-end is small. The expensive parts of RISC-V debug are the trigger comparators and, where used, the System Bus Access master, and those are decisions you already made when you chose a core configuration.

### Is an exposed SWD port a security problem?

Yes, on a production part. Two pins give full register and memory access. Plan for Debug Module authentication or a fuse or lifecycle lock before tape-out, not after.

08 · Contact

## Where it would help to talk.

Three conversations are worth having: board and SoC teams feeling the pin-count pressure, debug tooling vendors who could help settle the upstreaming question, and education or research groups for whom two wires and a cheap probe is a lower barrier than a JTAG setup.

https://saketsinha.de/VexRiscv-Debug/

[Project overview and milestones](https://saketsinha.de/VexRiscv-Debug/) · [Standard debug in VexRiscv](https://saketsinha.de/standard-debug-vexriscv/)

Saket Sinha · Berlin · sole developer SWD Debug support in VexRiscv · NLnet NGI0 Commons Fund, grant 2025-02-159 RTL merged under the upstream project licences. Upstream maintainer: Charles Papon (VexRiscv).
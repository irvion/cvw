///////////////////////////////////////////
// privileged.sv
//
// Written: David_Harris@hmc.edu 5 January 2021
// Modified: 
//
// Purpose: Implements the CSRs, Exceptions, and Privileged operations
//          See RISC-V Privileged Mode Specification 20190608 
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, 
// modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software 
// is furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES 
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT 
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
///////////////////////////////////////////

`include "wally-config.vh"

// *** remove signals not needed by PMA/PMP now that it is moved
module privileged (
  input  logic             clk, reset,
  input  logic             FlushD, FlushE, FlushM, FlushW, StallD, StallE, StallM, StallW,
  input  logic             CSRReadM, CSRWriteM,
  input  logic [`XLEN-1:0] SrcAM,
  input  logic [`XLEN-1:0] PCF,PCD,PCE,PCM,
  input  logic [31:0]      InstrD, InstrE, InstrM, InstrW,
  output logic [`XLEN-1:0] CSRReadValM, CSRReadValW,
  output logic [`XLEN-1:0] PrivilegedNextPCM,
  output logic             RetM, TrapM, NonBusTrapM,
  output logic             ITLBFlushF, DTLBFlushM,
  input  logic             InstrValidM,InstrValidW, CommittedM,
  input  logic             FloatRegWriteW, LoadStallD,
  input  logic 		   BPPredDirWrongM,
  input  logic 		   BTBPredPCWrongM,
  input  logic 		   RASPredPCWrongM,
  input  logic 		   BPPredClassNonCFIWrongM,
  input  logic [4:0]       InstrClassM,
  input  logic             PrivilegedM,
  input  logic             ITLBInstrPageFaultF, DTLBLoadPageFaultM, DTLBStorePageFaultM,
  input  logic             WalkerInstrPageFaultF, WalkerLoadPageFaultM, WalkerStorePageFaultM,
  input  logic             InstrMisalignedFaultM, IllegalIEUInstrFaultD, IllegalFPUInstrD,
  input  logic             LoadMisalignedFaultM,
  input  logic             StoreMisalignedFaultM,
  input  logic             TimerIntM, ExtIntM, SwIntM,
  input  logic [63:0]      MTIME_CLINT, MTIMECMP_CLINT,
  input  logic [`XLEN-1:0] InstrMisalignedAdrM, MemAdrM,
  input  logic [4:0]       SetFflagsM,

  // Trap signals from pmp/pma in mmu
  // *** do these need to be split up into one for dmem and one for ifu?
  // instead, could we only care about the instr and F pins that come from ifu and only care about the load/store and m pins that come from dmem?
  
  input logic PMAInstrAccessFaultF, PMPInstrAccessFaultF,
  input logic PMALoadAccessFaultM, PMPLoadAccessFaultM,
  input logic PMAStoreAccessFaultM, PMPStoreAccessFaultM,

  output logic		   IllegalFPUInstrE,
  output logic [1:0]       PrivilegeModeW,
  output logic [`XLEN-1:0] SATP_REGW,
  output logic             STATUS_MXR, STATUS_SUM,
  output logic [63:0]      PMPCFG01_REGW, PMPCFG23_REGW,
  output var logic [`XLEN-1:0] PMPADDR_ARRAY_REGW [`PMP_ENTRIES-1:0], 
  output logic [2:0]       FRM_REGW
);

  logic [1:0] NextPrivilegeModeM;

  logic [`XLEN-1:0] CauseM, NextFaultMtvalM;
  logic [`XLEN-1:0] MEPC_REGW, SEPC_REGW, UEPC_REGW, UTVEC_REGW, STVEC_REGW, MTVEC_REGW;
//  logic [11:0] MEDELEG_REGW, MIDELEG_REGW, SEDELEG_REGW, SIDELEG_REGW;
  logic [`XLEN-1:0] MEDELEG_REGW, MIDELEG_REGW, SEDELEG_REGW, SIDELEG_REGW;

  logic uretM, sretM, mretM, ecallM, ebreakM, wfiM, sfencevmaM;
  logic IllegalCSRAccessM;
  logic IllegalIEUInstrFaultE, IllegalIEUInstrFaultM;
  logic IllegalFPUInstrM;
  logic LoadPageFaultM, StorePageFaultM; 
  logic InstrPageFaultF, InstrPageFaultD, InstrPageFaultE, InstrPageFaultM;
  logic InstrAccessFaultF, InstrAccessFaultD, InstrAccessFaultE, InstrAccessFaultM;
  logic LoadAccessFaultM, StoreAccessFaultM;
  logic IllegalInstrFaultM;

  logic BreakpointFaultM, EcallFaultM;
  logic MTrapM, STrapM, UTrapM;
  logic InterruptM; 

  logic [1:0] STATUS_MPP;
  logic       STATUS_SPP, STATUS_TSR, STATUS_MPRV; // **** status mprv is unused outside of the csr module as of 4 June 2021. should it be deleted alltogether from the module, or should I leav the pin here in case someone needs it? 
  logic       STATUS_MIE, STATUS_SIE;
  logic [11:0] MIP_REGW, MIE_REGW, SIP_REGW, SIE_REGW;
  logic md, sd;


  ///////////////////////////////////////////
  // track the current privilege level
  ///////////////////////////////////////////

  // get bits of DELEG registers based on CAUSE
//  assign md = CauseM[`XLEN-1] ? MIDELEG_REGW[CauseM[3:0]] : MEDELEG_REGW[CauseM[3:0]];
//  assign sd = CauseM[`XLEN-1] ? SIDELEG_REGW[CauseM[3:0]] : SEDELEG_REGW[CauseM[3:0]]; // depricated
  assign md = CauseM[`XLEN-1] ? MIDELEG_REGW[CauseM[`LOG_XLEN-1:0]] : MEDELEG_REGW[CauseM[`LOG_XLEN-1:0]];
  assign sd = CauseM[`XLEN-1] ? SIDELEG_REGW[CauseM[`LOG_XLEN-1:0]] : SEDELEG_REGW[CauseM[`LOG_XLEN-1:0]]; // depricated
  
  // PrivilegeMode FSM
  always_comb
  /*  if      (reset) NextPrivilegeModeM = `M_MODE; // Privilege resets to 11 (Machine Mode) // moved reset to flop
    else */ if (mretM) NextPrivilegeModeM = STATUS_MPP;
    else if (sretM) NextPrivilegeModeM = {1'b0, STATUS_SPP};
    else if (uretM) NextPrivilegeModeM = `U_MODE;
    else if (TrapM) begin // Change privilege based on DELEG registers (see 3.1.8)
      if (PrivilegeModeW == `U_MODE)
        if (`N_SUPPORTED & `U_SUPPORTED & md & sd) NextPrivilegeModeM = `U_MODE;
        else if (`S_SUPPORTED & md)                NextPrivilegeModeM = `S_MODE;
        else                                       NextPrivilegeModeM = `M_MODE;
      else if (PrivilegeModeW == `S_MODE) 
        if (`S_SUPPORTED & md)                     NextPrivilegeModeM = `S_MODE;
        else                                       NextPrivilegeModeM = `M_MODE;
      else                                         NextPrivilegeModeM = `M_MODE;
    end else                                       NextPrivilegeModeM = PrivilegeModeW;

  flopenl #(2) privmodereg(clk, reset, ~StallW, NextPrivilegeModeM, `M_MODE, PrivilegeModeW);

  ///////////////////////////////////////////
  // decode privileged instructions
  ///////////////////////////////////////////

  privdec pmd(.InstrM(InstrM[31:20]), .*);

  ///////////////////////////////////////////
  // Control and Status Registers
  ///////////////////////////////////////////

  csr csr(.*);

  ///////////////////////////////////////////
  // Extract exceptions by name and handle them 
  ///////////////////////////////////////////

  assign BreakpointFaultM = ebreakM; // could have other causes too
  assign EcallFaultM = ecallM;
  assign ITLBFlushF = sfencevmaM;
  assign DTLBFlushM = sfencevmaM;

  // A page fault might occur because of insufficient privilege during a TLB
  // lookup or a improperly formatted page table during walking
  assign InstrPageFaultF = ITLBInstrPageFaultF || WalkerInstrPageFaultF;
  assign LoadPageFaultM = DTLBLoadPageFaultM || WalkerLoadPageFaultM;
  assign StorePageFaultM = DTLBStorePageFaultM || WalkerStorePageFaultM;

  assign InstrAccessFaultF = PMAInstrAccessFaultF || PMPInstrAccessFaultF;
  assign LoadAccessFaultM  = PMALoadAccessFaultM || PMPLoadAccessFaultM;
  assign StoreAccessFaultM  = PMAStoreAccessFaultM || PMPStoreAccessFaultM;

  // pipeline fault signals
  flopenrc #(2) faultregD(clk, reset, FlushD, ~StallD,
                  {InstrPageFaultF, InstrAccessFaultF},
                  {InstrPageFaultD, InstrAccessFaultD});
  flopenrc #(4) faultregE(clk, reset, FlushE, ~StallE,
                  {IllegalIEUInstrFaultD, InstrPageFaultD, InstrAccessFaultD, IllegalFPUInstrD}, // ** vs IllegalInstrFaultInD
                  {IllegalIEUInstrFaultE, InstrPageFaultE, InstrAccessFaultE, IllegalFPUInstrE});
  flopenrc #(4) faultregM(clk, reset, FlushM, ~StallM,
                  {IllegalIEUInstrFaultE, InstrPageFaultE, InstrAccessFaultE, IllegalFPUInstrE},
                  {IllegalIEUInstrFaultM, InstrPageFaultM, InstrAccessFaultM, IllegalFPUInstrM});

  trap trap(.*);

endmodule





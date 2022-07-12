///////////////////////////////////////////
// uart_apb.sv
//
// Written: David_Harris@hmc.edu 21 January 2021
// Modified: 
//
// Purpose: Interface to Universial Asynchronous Receiver/ Transmitter with FIFOs
//          Emulates interface of Texas Instruments PC165550D
//          Compatible with UART in Imperas Virtio model ***
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// MIT LICENSE
// Permission is hereby granted, free of charge, to any person obtaining a copy of this 
// software and associated documentation files (the "Software"), to deal in the Software 
// without restriction, including without limitation the rights to use, copy, modify, merge, 
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons 
// to whom the Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or 
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
//   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
//   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
//   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
//   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
//   OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module uart_apb (
  input  logic             PCLK, PRESETn,
  input  logic             PSEL,
  input  logic [2:0]      PADDR, 
  input  logic [`XLEN-1:0] PWDATA,
  input  logic [`XLEN/8-1:0] PSTRB,
  input  logic             PWRITE,
  input  logic             PENABLE,
  output logic [`XLEN-1:0] PRDATA,
  output logic             PREADY,
/*
  input  logic             HCLK, HRESETn, 
  input  logic             HSELUART,
  input  logic [2:0]       HADDR,
  input  logic             HWRITE,
  input  logic [`XLEN-1:0] PWDATA,
  output logic [`XLEN-1:0] HREADUART,
  output logic             HRESPUART, HREADYUART, */
  (* mark_debug = "true" *) input  logic             SIN, DSRb, DCDb, CTSb, RIb,    // from E1A driver from RS232 interface
  (* mark_debug = "true" *) output logic             SOUT, RTSb, DTRb, // to E1A driver to RS232 interface
  (* mark_debug = "true" *) output logic             OUT1b, OUT2b, INTR, TXRDYb, RXRDYb);         // to CPU

  // UART interface signals
  logic [2:0]      entry;
  logic            MEMRb, MEMWb, memread, memwrite;
  logic [7:0]      Din, Dout;

  assign memwrite = PWRITE & PENABLE & PSEL;  // only write in access phase
  assign memread  = ~PWRITE & PENABLE & PSEL;  
  assign PREADY = 1'b1; // CLINT never takes >1 cycle to respond
  assign entry = PADDR[2:0];
  assign MEMRb = ~memread;
  assign MEMWb = ~memwrite;

/*
  // rename processor interface signals to match PC16550D and provide one-byte interface
  flopr #(1)  memreadreg(HCLK, ~HRESETn, (HSELUART & ~HWRITE), memread);
  flopr #(1) memwritereg(HCLK, ~HRESETn, (HSELUART &  HWRITE), memwrite);
  flopr #(3)   haddrreg(HCLK, ~HRESETn, HADDR[2:0], A);
  assign MEMRb = ~memread;
  assign MEMWb = ~memwrite;

  assign HRESPUART = 0; // OK
  assign HREADYUART = 1; // should idle high during address phase and respond high when done; will need to be modified if UART ever needs more than 1 cycle to do something
*/
  if (`XLEN == 64) begin:uart
    always_comb begin
      PRDATA = {Dout, Dout, Dout, Dout, Dout, Dout, Dout, Dout};
      case (entry)
        3'b000: Din = PWDATA[7:0];
        3'b001: Din = PWDATA[15:8];
        3'b010: Din = PWDATA[23:16];
        3'b011: Din = PWDATA[31:24];
        3'b100: Din = PWDATA[39:32];
        3'b101: Din = PWDATA[47:40];
        3'b110: Din = PWDATA[55:48];
        3'b111: Din = PWDATA[63:56];
      endcase 
    end 
  end else begin:uart // 32-bit
    always_comb begin
      PRDATA = {Dout, Dout, Dout, Dout};
      case (entry[1:0])
        2'b00: Din = PWDATA[7:0];
        2'b01: Din = PWDATA[15:8];
        2'b10: Din = PWDATA[23:16];
        2'b11: Din = PWDATA[31:24];
      endcase
    end
  end
  
  logic BAUDOUTb;  // loop tx clock BAUDOUTb back to rx clock RCLK
  // *** make sure reads don't occur on UART unless fully selected because they could change state.  This applies to all peripherals
  uartPC16550D u(  
    // Processor Interface
    .PCLK, .PRESETn,
    .A(entry), .Din, 
    .Dout,
    .MEMRb, .MEMWb, 
    .INTR, .TXRDYb, .RXRDYb,
    // Clocks
    .BAUDOUTb, .RCLK(BAUDOUTb),
    // E1A Driver
    .SIN, .DSRb, .DCDb, .CTSb, .RIb,
    .SOUT, .RTSb, .DTRb, .OUT1b, .OUT2b
);

endmodule

///////////////////////////////////////////
// clmul.sv
//
// Written: Kevin Kim <kekim@hmc.edu> and Kip Macsai-Goren <kmacsaigoren@hmc.edu>
// Created: 1 February 2023
// Modified: 
//
// Purpose: Carry-Less multiplication unit
//
// Documentation: RISC-V System on Chip Design Chapter ***
// 
// A component of the CORE-V-WALLY configurable RISC-V project.
// 
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file 
// except in compliance with the License, or, at your option, the Apache License version 2.0. You 
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the 
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
// either express or implied. See the License for the specific language governing permissions 
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module clmul #(parameter WIDTH=32) (
  input  logic [WIDTH-1:0] A, B,             // Operands
  output logic [WIDTH-1:0] ClmulResult);     // ZBS result

  logic [(WIDTH*WIDTH)-1:0] s;               // intermediary signals for carry-less multiply
  
  integer i;
  integer j;

  always_comb begin
    for (i=0;i<WIDTH;i++) begin: outer
      s[WIDTH*i]=A[0]&B[i];
      for (j=1;j<=i;j++) begin: inner
        s[WIDTH*i+j] = (A[j]&B[i-j])^s[WIDTH*i+j-1];
      end
      ClmulResult[i] = s[WIDTH*i+j-1];
    end
  end

endmodule



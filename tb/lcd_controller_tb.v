`timescale 1ns/1ps
//======================================================================
//  lcd_controller_tb.v -- self-checking simulation testbench
//
//  Runs the full init + write sequence with scaled-down timing, records
//  every byte latched on the falling edge of EN, and compares the
//  captured stream against the expected HD44780 sequence.
//======================================================================
module lcd_controller_tb;

    reg        clk = 0;
    reg        rst = 1;
    wire       rs, rw, en, ready;
    wire [7:0] data;

    lcd_controller #(.CLK_HZ(1_000_000), .EN_US(2)) dut (
        .clk(clk), .rst(rst), .rs(rs), .rw(rw),
        .en(en), .data(data), .ready(ready)
    );

    always #5 clk = ~clk;

    // ---- expected byte stream -------------------------------------
    localparam integer N = 28;
    reg [7:0] exp_data [0:N-1];
    reg       exp_rs   [0:N-1];
    integer   i, idx = 0, errors = 0;

    initial begin
        //                             rs
        exp_data[0]=8'h38; exp_rs[0]=0;   // Function Set
        exp_data[1]=8'h0C; exp_rs[1]=0;   // Display ON
        exp_data[2]=8'h01; exp_rs[2]=0;   // Clear
        exp_data[3]=8'h06; exp_rs[3]=0;   // Entry Mode
        exp_data[4]=8'h80; exp_rs[4]=0;   // DDRAM line 1
        exp_data[5]="S";  exp_rs[5]=1;
        exp_data[6]="A";  exp_rs[6]=1;
        exp_data[7]="L";  exp_rs[7]=1;
        exp_data[8]="S";  exp_rs[8]=1;
        exp_data[9]="A";  exp_rs[9]=1;
        exp_data[10]="B"; exp_rs[10]=1;
        exp_data[11]="E"; exp_rs[11]=1;
        exp_data[12]="E"; exp_rs[12]=1;
        exp_data[13]="L"; exp_rs[13]=1;
        exp_data[14]=" "; exp_rs[14]=1;
        exp_data[15]="K"; exp_rs[15]=1;
        exp_data[16]=8'hC0; exp_rs[16]=0; // DDRAM line 2
        exp_data[17]="S"; exp_rs[17]=1;
        exp_data[18]="P"; exp_rs[18]=1;
        exp_data[19]="A"; exp_rs[19]=1;
        exp_data[20]="R"; exp_rs[20]=1;
        exp_data[21]="T"; exp_rs[21]=1;
        exp_data[22]="A"; exp_rs[22]=1;
        exp_data[23]="N"; exp_rs[23]=1;
        exp_data[24]="6"; exp_rs[24]=1;
        exp_data[25]=" "; exp_rs[25]=1;
        exp_data[26]="L"; exp_rs[26]=1;
        exp_data[27]="C"; exp_rs[27]=1;
    end

    // HD44780 latches on the falling edge of EN
    always @(negedge en) begin
        if (!rst) begin
            if (idx < N) begin
                if (data !== exp_data[idx] || rs !== exp_rs[idx]) begin
                    $display("  [%2d] MISMATCH got %s 0x%02h, expected %s 0x%02h",
                             idx, rs?"DATA":"CMD ", data,
                             exp_rs[idx]?"DATA":"CMD ", exp_data[idx]);
                    errors = errors + 1;
                end else begin
                    $display("  [%2d] %s 0x%02h (%c)  ok", idx, rs?"DATA":"CMD ",
                             data, (data>=8'h20 && data<8'h7f)?data:".");
                end
            end
            idx = idx + 1;
        end
    end

    integer clear_us;
    initial begin
        $dumpfile("lcd_sim.vcd");
        $dumpvars(0, lcd_controller_tb);
        #100 rst = 0;
        wait (ready);
        #1000;

        // Timing check against the datasheet, done on the design's own
        // parameters rather than on simulation time -- the testbench runs
        // with compressed timing, so raw sim time means nothing here.
        $display("");
        clear_us = dut.CLEAR_TICKS * dut.EN_US;
        $display("Clear Display settle: %0d ticks x %0d us = %0d us",
                 dut.CLEAR_TICKS, dut.EN_US, clear_us);
        if (clear_us < 1520) begin
            $display("  ** FAIL: HD44780 Clear Display needs 1520 us **");
            errors = errors + 1;
        end else
            $display("  ok: clears the 1520 us the datasheet requires");

        $display("");
        if (idx < N) begin
            $display("FAIL: only %0d bytes written, expected %0d", idx, N);
            errors = errors + 1;
        end
        if (errors == 0) $display("ALL CHECKS PASSED (%0d bytes verified)", N);
        else             $display("%0d FAILURES", errors);
        $finish;
    end

endmodule

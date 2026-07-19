`timescale 1ns/1ps
//======================================================================
//  lcd_controller_tb.v  -- simulation testbench
//  Speeds up timing (small CLK_HZ / EN_US) so the whole init + write
//  sequence completes quickly in simulation. Dumps a VCD you can open
//  in ISim / GTKWave to see rs, rw, en and the data bus.
//======================================================================
module lcd_controller_tb;

    reg        clk = 0;
    reg        rst = 1;
    wire       rs, rw, en;
    wire [7:0] data;

    // tiny timing params so sim runs fast
    lcd_controller #(.CLK_HZ(1_000_000), .EN_US(2)) dut (
        .clk (clk),
        .rst (rst),
        .rs  (rs),
        .rw  (rw),
        .en  (en),
        .data(data)
    );

    always #5 clk = ~clk;          // 100 MHz sim clock

    // capture each byte on the falling edge of EN
    always @(negedge en) begin
        if (!rst)
            $display("t=%0t  %s  byte=0x%02h (%c)",
                     $time, rs ? "DATA":"CMD ", data,
                     (data >= 8'h20 && data < 8'h7f) ? data : ".");
    end

    initial begin
        $dumpfile("lcd_sim.vcd");
        $dumpvars(0, lcd_controller_tb);
        #100 rst = 0;              // release reset
        #4_000_000;               // run long enough to finish both lines
        $display("Simulation done.");
        $finish;
    end

endmodule

//======================================================================
//  lcd_controller.v
//  16x2 Character LCD (HD44780) driver in 8-bit mode for Xilinx Spartan-6
//
//  Design notes (matches the documented FSM):
//    * Interface : 8-bit, 2 lines, 5x8 dots  (Function Set = 0x38)
//    * Init      : Function Set -> Display ON -> Clear Display -> Entry Mode
//    * Data      : WRITE_DATA state drives rs=1, rw=0, and streams ASCII
//                  bytes from an internal message array, incrementing
//                  char_count until the whole string is written.
//
//  RS = 0 -> command,  RS = 1 -> data.  RW tied low (write-only).
//  EN is pulsed high for one enable window per byte.
//
//  NOTE: This RTL was reconstructed to match the module described in the
//  project slides after the original .v file was lost. The design was
//  built and run on a real Spartan-6 board (see docs/images).
//======================================================================
module lcd_controller #(
    parameter integer CLK_HZ   = 50_000_000,   // board oscillator
    parameter integer EN_US    = 50            // enable/settle window (us)
)(
    input  wire       clk,
    input  wire       rst,        // active-high reset
    output reg        rs,         // 0 = command, 1 = data
    output wire       rw,         // always 0 (write)
    output reg        en,         // enable strobe
    output reg [7:0]  data        // 8-bit data/command bus
);

    assign rw = 1'b0;             // write-only

    // ---- timing: one "tick" every EN_US microseconds ----------------
    localparam integer TICKS = (CLK_HZ/1_000_000)*EN_US;
    reg [$clog2(TICKS+1)-1:0] div = 0;
    reg tick = 1'b0;
    always @(posedge clk) begin
        if (rst) begin div <= 0; tick <= 1'b0; end
        else if (div == TICKS-1) begin div <= 0; tick <= 1'b1; end
        else begin div <= div + 1'b1; tick <= 1'b0; end
    end

    // ---- HD44780 command set ----------------------------------------
    localparam [7:0] CMD_FUNCTION_SET = 8'h38; // 8-bit, 2 line, 5x8
    localparam [7:0] CMD_DISPLAY_ON   = 8'h0C; // display on, cursor off
    localparam [7:0] CMD_CLEAR        = 8'h01; // clear display
    localparam [7:0] CMD_ENTRY_MODE   = 8'h06; // increment, no shift
    localparam [7:0] CMD_LINE1        = 8'h80; // DDRAM addr, line 1
    localparam [7:0] CMD_LINE2        = 8'hC0; // DDRAM addr, line 2

    // ---- message ROM (edit these to change what is displayed) --------
    localparam integer LEN1 = 11;
    localparam integer LEN2 = 12;
    // "SALSABEEL K"
    reg [7:0] line1 [0:LEN1-1];
    // "SPARTAN6 LCD"
    reg [7:0] line2 [0:LEN2-1];
    integer k;
    initial begin
        line1[0]="S"; line1[1]="A"; line1[2]="L"; line1[3]="S"; line1[4]="A";
        line1[5]="B"; line1[6]="E"; line1[7]="E"; line1[8]="L"; line1[9]=" ";
        line1[10]="K";
        line2[0]="S"; line2[1]="P"; line2[2]="A"; line2[3]="R"; line2[4]="T";
        line2[5]="A"; line2[6]="N"; line2[7]="6"; line2[8]=" "; line2[9]="L";
        line2[10]="C"; line2[11]="D";
    end

    // ---- FSM ---------------------------------------------------------
    localparam [3:0]
        S_POWER_UP   = 4'd0,
        S_FUNCTION   = 4'd1,
        S_DISP_ON    = 4'd2,
        S_CLEAR      = 4'd3,
        S_ENTRY      = 4'd4,
        S_SET_LINE1  = 4'd5,
        S_WRITE1     = 4'd6,
        S_SET_LINE2  = 4'd7,
        S_WRITE2     = 4'd8,
        S_DONE       = 4'd9;

    reg [3:0]  state = S_POWER_UP;
    reg [15:0] boot  = 0;            // power-on delay counter (ticks)
    reg        phase = 0;            // 0 = present byte + EN high, 1 = EN low
    integer    char_count = 0;

    always @(posedge clk) begin
        if (rst) begin
            state <= S_POWER_UP; en <= 1'b0; rs <= 1'b0;
            data <= 8'h00; boot <= 0; phase <= 0; char_count <= 0;
        end else if (tick) begin
            case (state)
            // wait > ~15 ms after power-up before first command
            S_POWER_UP: begin
                en <= 1'b0; rs <= 1'b0;
                if (boot < 16'd400) boot <= boot + 1'b1;
                else state <= S_FUNCTION;
            end

            // ---- command states share one EN-pulse pattern via 'phase'
            S_FUNCTION:  begin rs<=0; data<=CMD_FUNCTION_SET; pulse(S_DISP_ON);  end
            S_DISP_ON:   begin rs<=0; data<=CMD_DISPLAY_ON;   pulse(S_CLEAR);    end
            S_CLEAR:     begin rs<=0; data<=CMD_CLEAR;        pulse(S_ENTRY);    end
            S_ENTRY:     begin rs<=0; data<=CMD_ENTRY_MODE;   pulse(S_SET_LINE1);end
            S_SET_LINE1: begin rs<=0; data<=CMD_LINE1;        pulse(S_WRITE1);   end

            // ---- WRITE_DATA (line 1): rs=1, stream ASCII, count up -----
            S_WRITE1: begin
                rs <= 1'b1;
                data <= line1[char_count];
                if (phase == 0) begin en <= 1'b1; phase <= 1; end
                else begin
                    en <= 1'b0; phase <= 0;
                    if (char_count == LEN1-1) begin
                        char_count <= 0; state <= S_SET_LINE2;
                    end else char_count <= char_count + 1;
                end
            end

            S_SET_LINE2: begin rs<=0; data<=CMD_LINE2; pulse(S_WRITE2); end

            S_WRITE2: begin
                rs <= 1'b1;
                data <= line2[char_count];
                if (phase == 0) begin en <= 1'b1; phase <= 1; end
                else begin
                    en <= 1'b0; phase <= 0;
                    if (char_count == LEN2-1) state <= S_DONE;
                    else char_count <= char_count + 1;
                end
            end

            S_DONE: begin en <= 1'b0; end   // hold display
            default: state <= S_POWER_UP;
            endcase
        end
    end

    // one-tick EN strobe for command bytes, then advance to next_state
    task pulse(input [3:0] next_state);
        begin
            if (phase == 0) begin en <= 1'b1; phase <= 1; end
            else begin en <= 1'b0; phase <= 0; state <= next_state; end
        end
    endtask

endmodule

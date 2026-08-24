//======================================================================
//  lcd_controller.v
//  16x2 HD44780 character-LCD driver, 8-bit mode, for Xilinx Spartan-6
//
//  FSM:
//    POWER_UP -> FUNCTION_SET -> DISPLAY_ON -> CLEAR -> CLEAR_WAIT
//             -> ENTRY_MODE -> SET_LINE1 -> WRITE1
//             -> SET_LINE2 -> WRITE2 -> DONE
//
//    RS = 0 -> command,  RS = 1 -> data.  RW tied low (write-only).
//    EN is pulsed high for one settle window per byte; the HD44780
//    latches the bus on the FALLING edge of EN.
//
//  ATTRIBUTION
//    Adapted from an open-source HD44780 Verilog driver that streamed
//    ASCII from an internal message array. The original source was not
//    recorded at the time and could not be located afterwards.
//
//    The original project .v was subsequently lost; this file was
//    reconstructed to match the FSM documented in the project report,
//    then corrected (see CLEAR_WAIT below). The board photographs in
//    docs/images are from the original hardware run.
//======================================================================
module lcd_controller #(
    parameter integer CLK_HZ = 50_000_000,   // board oscillator
    parameter integer EN_US  = 50            // enable/settle window (us)
)(
    input  wire       clk,
    input  wire       rst,        // active-high reset
    output reg        rs,         // 0 = command, 1 = data
    output wire       rw,         // always 0 (write)
    output reg        en,         // enable strobe
    output reg [7:0]  data,       // 8-bit command/data bus
    output wire       ready       // high once the display has been written
);

    assign rw = 1'b0;             // write-only: the busy flag is never read,
                                  // so every wait below is a fixed delay

    // ---- timing: one "tick" every EN_US microseconds -----------------
    localparam integer TICKS = (CLK_HZ/1_000_000)*EN_US;
    reg [$clog2(TICKS+1)-1:0] div = 0;
    reg tick = 1'b0;
    always @(posedge clk) begin
        if (rst) begin div <= 0; tick <= 1'b0; end
        else if (div == TICKS-1) begin div <= 0; tick <= 1'b1; end
        else begin div <= div + 1'b1; tick <= 1'b0; end
    end

    // ---- HD44780 command set -----------------------------------------
    localparam [7:0] CMD_FUNCTION_SET = 8'h38; // 8-bit, 2 line, 5x8
    localparam [7:0] CMD_DISPLAY_ON   = 8'h0C; // display on, cursor off
    localparam [7:0] CMD_CLEAR        = 8'h01; // clear display
    localparam [7:0] CMD_ENTRY_MODE   = 8'h06; // increment, no shift
    localparam [7:0] CMD_LINE1        = 8'h80; // DDRAM address, line 1
    localparam [7:0] CMD_LINE2        = 8'hC0; // DDRAM address, line 2

    // ---- datasheet delays, expressed in ticks ------------------------
    //  Most commands execute in ~37 us, so one EN_US window covers them.
    //  CLEAR DISPLAY is the exception at 1.52 ms — roughly 30x longer.
    //  Without an explicit wait the next command is issued while the
    //  controller is still clearing, and it is ignored: the classic
    //  symptom is the first characters of line 1 going missing.
    localparam integer BOOT_TICKS  = (20000 / EN_US) + 1;   // >15 ms power-on
    localparam integer CLEAR_TICKS = (2000  / EN_US) + 1;   // >1.52 ms, w/ margin

    // ---- message ROM (edit to change what is displayed) ---------------
    localparam integer LEN1 = 11;
    localparam integer LEN2 = 12;
    reg [7:0] line1 [0:LEN1-1];    // "SALSABEEL K"
    reg [7:0] line2 [0:LEN2-1];    // "SPARTAN6 LCD"
    initial begin
        line1[0]="S"; line1[1]="A"; line1[2]="L"; line1[3]="S"; line1[4]="A";
        line1[5]="B"; line1[6]="E"; line1[7]="E"; line1[8]="L"; line1[9]=" ";
        line1[10]="K";
        line2[0]="S"; line2[1]="P"; line2[2]="A"; line2[3]="R"; line2[4]="T";
        line2[5]="A"; line2[6]="N"; line2[7]="6"; line2[8]=" "; line2[9]="L";
        line2[10]="C"; line2[11]="D";
    end

    // ---- FSM ----------------------------------------------------------
    localparam [3:0]
        S_POWER_UP   = 4'd0,
        S_FUNCTION   = 4'd1,
        S_DISP_ON    = 4'd2,
        S_CLEAR      = 4'd3,
        S_CLEAR_WAIT = 4'd4,
        S_ENTRY      = 4'd5,
        S_SET_LINE1  = 4'd6,
        S_WRITE1     = 4'd7,
        S_SET_LINE2  = 4'd8,
        S_WRITE2     = 4'd9,
        S_DONE       = 4'd10;

    reg [3:0]  state = S_POWER_UP;
    reg [15:0] wait_ctr = 0;       // shared by POWER_UP and CLEAR_WAIT
    reg        phase = 1'b0;       // 0 = present byte + EN high, 1 = EN low
    reg [3:0]  char_count = 0;     // sized, not an unbounded integer

    assign ready = (state == S_DONE);

    always @(posedge clk) begin
        if (rst) begin
            state <= S_POWER_UP; en <= 1'b0; rs <= 1'b0;
            data <= 8'h00; wait_ctr <= 0; phase <= 1'b0; char_count <= 0;
        end else if (tick) begin
            case (state)

            // wait out the power-on time before the first command
            S_POWER_UP: begin
                en <= 1'b0; rs <= 1'b0;
                if (wait_ctr < BOOT_TICKS) wait_ctr <= wait_ctr + 1'b1;
                else begin wait_ctr <= 0; state <= S_FUNCTION; end
            end

            // ---- command states share one EN-pulse pattern via 'phase'
            S_FUNCTION:  begin rs<=0; data<=CMD_FUNCTION_SET; pulse(S_DISP_ON);   end
            S_DISP_ON:   begin rs<=0; data<=CMD_DISPLAY_ON;   pulse(S_CLEAR);     end
            S_CLEAR:     begin rs<=0; data<=CMD_CLEAR;        pulse(S_CLEAR_WAIT);end

            // the long one — see CLEAR_TICKS above
            S_CLEAR_WAIT: begin
                en <= 1'b0;
                if (wait_ctr < CLEAR_TICKS) wait_ctr <= wait_ctr + 1'b1;
                else begin wait_ctr <= 0; state <= S_ENTRY; end
            end

            S_ENTRY:     begin rs<=0; data<=CMD_ENTRY_MODE;   pulse(S_SET_LINE1); end
            S_SET_LINE1: begin rs<=0; data<=CMD_LINE1;        pulse(S_WRITE1);    end

            // ---- WRITE_DATA (line 1): rs=1, stream ASCII, count up -----
            S_WRITE1: begin
                rs <= 1'b1;
                data <= line1[char_count];
                if (phase == 1'b0) begin en <= 1'b1; phase <= 1'b1; end
                else begin
                    en <= 1'b0; phase <= 1'b0;
                    if (char_count == LEN1-1) begin
                        char_count <= 0; state <= S_SET_LINE2;
                    end else char_count <= char_count + 1'b1;
                end
            end

            S_SET_LINE2: begin rs<=0; data<=CMD_LINE2; pulse(S_WRITE2); end

            S_WRITE2: begin
                rs <= 1'b1;
                data <= line2[char_count];
                if (phase == 1'b0) begin en <= 1'b1; phase <= 1'b1; end
                else begin
                    en <= 1'b0; phase <= 1'b0;
                    if (char_count == LEN2-1) state <= S_DONE;
                    else char_count <= char_count + 1'b1;
                end
            end

            S_DONE: begin en <= 1'b0; end     // hold the display
            default: state <= S_POWER_UP;
            endcase
        end
    end

    // one settle-window EN strobe for a command byte, then advance
    task pulse(input [3:0] next_state);
        begin
            if (phase == 1'b0) begin en <= 1'b1; phase <= 1'b1; end
            else begin en <= 1'b0; phase <= 1'b0; state <= next_state; end
        end
    endtask

endmodule

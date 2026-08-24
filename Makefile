# Simulate with Icarus Verilog
IVERILOG = iverilog -g2012

all: sim

sim:
	$(IVERILOG) -o lcd.out rtl/lcd_controller.v tb/lcd_controller_tb.v
	vvp lcd.out

wave: sim
	gtkwave lcd_sim.vcd

clean:
	rm -f lcd.out lcd_sim.vcd

.PHONY: all sim wave clean

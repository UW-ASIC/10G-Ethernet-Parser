# --- Verilator Project Makefile (Pure SystemVerilog TB) ---

TB_TOP = tb_ip_parser_header_extraction

RTL_SRC = ../../RTL/IP_Parser/ip_parser_header_extraction.sv
TB_SRC  = tb_ip_parser_header_extraction.sv

VERILATOR = verilator
VERILATOR_FLAGS = -Wall --binary --trace -j 0

BUILD_DIR = obj_dir
EXE_NAME = V$(TB_TOP)

.PHONY: all run compile clean

all: run

run: compile
	@echo "--------------------------------------------------------"
	@echo "Running Verilator Simulation..."
	@echo "--------------------------------------------------------"
	./$(BUILD_DIR)/$(EXE_NAME)

compile: $(BUILD_DIR)/$(EXE_NAME)

$(BUILD_DIR)/$(EXE_NAME): $(RTL_SRC) $(TB_SRC)
	@echo "--------------------------------------------------------"
	@echo "Verilating and Compiling Verilog Testbench..."
	@echo "--------------------------------------------------------"
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRC) $(TB_SRC) --top-module $(TB_TOP)

clean:
	@echo "Cleaning up build directory..."
	rm -rf $(BUILD_DIR)

package general_pkg;
    localparam int N     = 8;
    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    // mode[0] = load_en, mode[1] = compute_en. 2'b11 kullanilmaz -> HOLD gibi davranir.
    typedef enum logic [1:0] {
        MODE_HOLD    = 2'b00,
        MODE_LOAD    = 2'b01,
        MODE_COMPUTE = 2'b10
    } mode_t;

    typedef logic signed [ACT_W-1:0] act_t;
    typedef logic signed [ACC_W-1:0] acc_t;
endpackage
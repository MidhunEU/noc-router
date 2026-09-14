// 5-Port NoC Router verification (SystemVerilog, Synopsys VCS)
// design.sv (Design pane): package + interface + DUT + SVA (+define+ENABLE_SVA)

package router_pkg;

  parameter int NPORTS   = 5;  // N, S, E, W, Local
  parameter int DATA_W   = 32;
  parameter int NVC      = 2;
  parameter int BUF_DEP  = 8;
  parameter int MAX_PLEN = 10;

  typedef enum int {P_N = 0, P_S = 1, P_E = 2, P_W = 3, P_L = 4} port_t;

  typedef enum logic [1:0] {
    F_HEAD = 2'b00, F_BODY = 2'b01, F_TAIL = 2'b10, F_SINGLE = 2'b11
  } flit_t;

  // Header {type[31:30], vc[29], pad[28:27], tag[26:3], dest[2:0]}
  // Body/tail {type[31:30], payload[29:0]}: bit[29] is payload, not VC.
  function automatic logic [DATA_W-1:0] mk_head(input int vc, input int dest,
                                               input int tag);
    return {F_HEAD, vc[0], 2'b00, tag[23:0], dest[2:0]};
  endfunction

  function automatic logic [DATA_W-1:0] mk_body(input int payload);
    return {F_BODY, payload[29:0]};
  endfunction

  function automatic logic [DATA_W-1:0] mk_tail(input int payload);
    return {F_TAIL, payload[29:0]};
  endfunction

  function automatic flit_t get_ftype(input logic [DATA_W-1:0] flit);
    if (flit[31:30] == 2'b00)      return F_HEAD;
    else if (flit[31:30] == 2'b01) return F_BODY;
    else if (flit[31:30] == 2'b10) return F_TAIL;
    else                           return F_SINGLE;
  endfunction

  function automatic int get_dest(input logic [DATA_W-1:0] flit);
    return int'(flit[2:0]);
  endfunction

  function automatic int get_vc(input logic [DATA_W-1:0] flit);
    return int'(flit[29]);
  endfunction

endpackage


interface router_if (input logic clk, input logic rst_n);
  import router_pkg::*;

  logic [DATA_W-1:0] data_in   [NPORTS];
  logic              valid_in  [NPORTS];
  logic              ready_out [NPORTS];
  logic [DATA_W-1:0] data_out  [NPORTS];
  logic              valid_out [NPORTS];
  logic              ready_in  [NPORTS];

  clocking drv_cb @(posedge clk);
    output data_in, valid_in, ready_in;
    input  ready_out, data_out, valid_out;
  endclocking

  clocking mon_cb @(posedge clk);
    input data_in, valid_in, ready_out, data_out, valid_out, ready_in;
  endclocking

  modport dut (
    input  clk, rst_n, data_in, valid_in, ready_in,
    output ready_out, data_out, valid_out
  );

  modport tb (clocking drv_cb, clocking mon_cb);

endinterface


module noc_router
  import router_pkg::*;
(
  input  logic               clk, rst_n,
  input  logic [DATA_W-1:0] data_in   [NPORTS],
  input  logic              valid_in  [NPORTS],
  output logic              ready_out [NPORTS],
  output logic [DATA_W-1:0] data_out  [NPORTS],
  output logic              valid_out [NPORTS],
  input  logic              ready_in  [NPORTS]
);

  logic [DATA_W-1:0] fifo [NPORTS][NVC][BUF_DEP];
  int  wr_ptr [NPORTS][NVC];
  int  rd_ptr [NPORTS][NVC];
  int  count  [NPORTS][NVC];
  int  route  [NPORTS][NVC];
  bit  active [NPORTS][NVC];
  int  rr_ptr  [NPORTS];
  int  lock_in [NPORTS];
  int  lock_vc [NPORTS];
  bit  lock_on [NPORTS];
  int  cur_vc [NPORTS];  // VC opened by HEAD per input; BODY/TAIL follow it

  always_comb begin
    for (int i = 0; i < NPORTS; i++) begin
      ready_out[i] = 1'b0;
      for (int v = 0; v < NVC; v++)
        if (count[i][v] < BUF_DEP) ready_out[i] = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int i = 0; i < NPORTS; i++) begin
        for (int v = 0; v < NVC; v++) begin
          wr_ptr[i][v] <= 0;
          rd_ptr[i][v] <= 0;
          count[i][v]  <= 0;
          route[i][v]  <= 0;
          active[i][v] <= 1'b0;
        end
      end
      for (int o = 0; o < NPORTS; o++) begin
        valid_out[o] <= 1'b0;
        data_out[o]  <= '0;
        rr_ptr[o]    <= 0;
        lock_in[o]   <= -1;
        lock_vc[o]   <= 0;
        lock_on[o]   <= 1'b0;
      end
      for (int i = 0; i < NPORTS; i++)
        cur_vc[i] <= 0;
    end else begin : seq_blk
      int cnt_next[NPORTS][NVC];
      for (int i = 0; i < NPORTS; i++)
        for (int v = 0; v < NVC; v++)
          cnt_next[i][v] = count[i][v];

      for (int i = 0; i < NPORTS; i++) begin : push_loop
        int v;
        logic [1:0] ftype;
        if (valid_in[i] && ready_out[i]) begin
          ftype = data_in[i][31:30];
          if (ftype == 2'b00 || ftype == 2'b11) begin
            v = int'(data_in[i][29]);
            if (v < 0 || v >= NVC) v = 0;
            cur_vc[i] <= v;
          end else begin
            v = cur_vc[i];
          end
          if (cnt_next[i][v] < BUF_DEP) begin
            fifo[i][v][wr_ptr[i][v]] <= data_in[i];
            wr_ptr[i][v]             <= (wr_ptr[i][v] + 1) % BUF_DEP;
            cnt_next[i][v]            = cnt_next[i][v] + 1;
            if (data_in[i][31:30] == 2'b00) begin
              route[i][v]  <= int'(data_in[i][2:0]) % NPORTS;
              active[i][v] <= 1'b1;
            end else if (data_in[i][31:30] == 2'b10) begin
              active[i][v] <= 1'b0;
            end else if (data_in[i][31:30] == 2'b11) begin
              route[i][v]  <= int'(data_in[i][2:0]) % NPORTS;
              active[i][v] <= 1'b0;
            end
          end
        end
      end

      for (int o = 0; o < NPORTS; o++) begin : pop_loop
        int gi;
        int gv;
        bit found;
        gi = -1; gv = 0; found = 1'b0;
        if (lock_on[o] && lock_in[o] >= 0) begin : locked_blk
          int li;
          int lv;
          li = lock_in[o]; lv = lock_vc[o];
          if (li >= 0 && li < NPORTS && lv >= 0 && lv < NVC && count[li][lv] > 0) begin
            gi = li; gv = lv; found = 1'b1;
          end
        end else begin : rr_blk
          for (int k = 0; k < NPORTS && !found; k++) begin : k_loop
            int ii;
            ii = (rr_ptr[o] + k) % NPORTS;
            for (int vv = 0; vv < NVC && !found; vv++) begin : v_loop
              if (count[ii][vv] > 0) begin : req_blk
                logic [DATA_W-1:0] front;
                int dest;
                front = fifo[ii][vv][rd_ptr[ii][vv]];
                if (front[31:30] == 2'b00 || front[31:30] == 2'b11)
                  dest = int'(front[2:0]) % NPORTS;
                else
                  dest = route[ii][vv] % NPORTS;
                if (dest == o) begin
                  gi = ii; gv = vv; found = 1'b1;
                end
              end
            end
          end
        end
        if (found && ready_in[o]) begin : grant_blk
          logic [DATA_W-1:0] gflit;
          gflit = fifo[gi][gv][rd_ptr[gi][gv]];
          data_out[o]    <= gflit;
          valid_out[o]   <= 1'b1;
          rd_ptr[gi][gv] <= (rd_ptr[gi][gv] + 1) % BUF_DEP;
          cnt_next[gi][gv] = cnt_next[gi][gv] - 1;
          if (gflit[31:30] == 2'b00) begin
            lock_on[o] <= 1'b1; lock_in[o] <= gi; lock_vc[o] <= gv;
          end else if (gflit[31:30] == 2'b10 || gflit[31:30] == 2'b11) begin
            lock_on[o] <= 1'b0; lock_in[o] <= -1;
            rr_ptr[o]  <= (gi + 1) % NPORTS;
          end
        end else if (!ready_in[o] && valid_out[o]) begin
          data_out[o]  <= data_out[o];  // hold stable while stalled
          valid_out[o] <= 1'b1;
        end else if (found && !ready_in[o]) begin
          data_out[o]  <= fifo[gi][gv][rd_ptr[gi][gv]];
          valid_out[o] <= 1'b1;
        end else begin
          valid_out[o] <= 1'b0;
          data_out[o]  <= '0;
        end
      end

      for (int i = 0; i < NPORTS; i++)
        for (int v = 0; v < NVC; v++)
          count[i][v] <= cnt_next[i][v];
    end
  end

endmodule


`ifdef ENABLE_SVA
import router_pkg::*;

module sva_checker (
  input logic clk, rst_n,
  input logic [DATA_W-1:0] data_in   [NPORTS],
  input logic              valid_in  [NPORTS],
  input logic              ready_out [NPORTS],
  input logic [DATA_W-1:0] data_out  [NPORTS],
  input logic              valid_out [NPORTS],
  input logic              ready_in  [NPORTS]
);
  genvar g;

  generate for (g = 0; g < NPORTS; g++) begin : g_in_stable
    assert property (@(posedge clk) disable iff (!rst_n)
      valid_in[g] && !ready_out[g] |-> ##1 valid_in[g] && $stable(data_in[g]))
    else $error("[SVA] in[%0d] not stable under backpressure @%0t", g, $time);
  end : g_in_stable
  endgenerate

  generate for (g = 0; g < NPORTS; g++) begin : g_out_hold
    assert property (@(posedge clk) disable iff (!rst_n)
      valid_out[g] && !ready_in[g] |-> ##1 valid_out[g] && $stable(data_out[g]))
    else $error("[SVA] out[%0d] dropped under stall @%0t", g, $time);
  end : g_out_hold
  endgenerate

  generate for (g = 0; g < NPORTS; g++) begin : g_nox
    assert property (@(posedge clk) disable iff (!rst_n)
      valid_out[g] |-> !$isunknown(data_out[g]))
    else $error("[SVA] out[%0d] X-propagation @%0t", g, $time);
  end : g_nox
  endgenerate

  generate for (g = 0; g < NPORTS; g++) begin : g_dest
    assert property (@(posedge clk) disable iff (!rst_n)
      valid_out[g] && ready_in[g] && data_out[g][31:30] == 2'b00
      |-> data_out[g][2:0] < NPORTS)
    else $error("[SVA] out[%0d] illegal dest @%0t", g, $time);
  end : g_dest
  endgenerate

  generate for (g = 0; g < NPORTS; g++) begin : g_h2t
    cover property (@(posedge clk) disable iff (!rst_n)
      valid_out[g] && ready_in[g] && data_out[g][31:30] == 2'b00
      ##[1:50] valid_out[g] && ready_in[g] && data_out[g][31:30] == 2'b10);
  end : g_h2t
  endgenerate

  cover property (@(posedge clk) disable iff (!rst_n)
    (valid_out[0] || valid_out[1] || valid_out[2] || valid_out[3] || valid_out[4])
    && !(ready_in[0] && ready_in[1] && ready_in[2] && ready_in[3] && ready_in[4]));

  cover property (@(posedge clk) disable iff (!rst_n)
    valid_in[0] && valid_in[1]);

  generate for (g = 0; g < NPORTS; g++) begin : g_live
    assert property (@(posedge clk) disable iff (!rst_n)
      valid_out[g] |-> ##[1:20] ready_in[g])
    else $warning("[SVA] out[%0d] stall >20 cycles @%0t (backpressure)", g, $time);
  end : g_live
  endgenerate

endmodule

bind noc_router sva_checker u_sva (
  .clk(clk), .rst_n(rst_n),
  .data_in(data_in), .valid_in(valid_in), .ready_out(ready_out),
  .data_out(data_out), .valid_out(valid_out), .ready_in(ready_in)
);
`endif // ENABLE_SVA

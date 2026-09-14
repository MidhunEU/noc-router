// 5-Port NoC Router verification (SystemVerilog, Synopsys VCS)
// testbench.sv (Testbench pane): layered OOP TB + top_tb
// +MODE: 0 random, 1 hotspot(to 0), 2 all-to-one(to 2), 3 single, 4 stress
import router_pkg::*;


class ObsFlit;
  int                port;
  logic [DATA_W-1:0] data;

  function new(int p = 0, logic [DATA_W-1:0] d = '0);
    port = p; data = d;
  endfunction
endclass


class Packet;
  rand int src;
  rand int dest;
  rand int vc;
  rand int len;
  rand int tag;
  rand int seed;

  constraint c_addr {
    src  inside {[0:NPORTS-1]};
    dest inside {[0:NPORTS-1]};
    dest != src;
  }
  constraint c_vc  { vc  inside {[0:NVC-1]}; }
  constraint c_len { len inside {[1:MAX_PLEN]}; }
  constraint c_tag { tag inside {[0:1000000]}; }

  function void pre_randomize();
  endfunction

  task get_flits(output logic [DATA_W-1:0] q[$]);
    logic [DATA_W-1:0] h;
    q.delete();
    if (len == 1) begin
      h = mk_head(vc % NVC, dest, tag);
      h[31:30] = F_SINGLE;
      q.push_back(h);
    end else begin
      q.push_back(mk_head(vc % NVC, dest, tag));
      for (int i = 0; i < len - 2; i++)
        q.push_back(mk_body(seed + i));
      q.push_back(mk_tail(seed + len));
    end
  endtask

  function void display(string pre = "PKT");
    $display("[%0t] %s src=%0d dest=%0d vc=%0d len=%0d tag=%0d",
             $time, pre, src, dest, vc, len, tag);
  endfunction
endclass


class HotspotPacket extends Packet;
  constraint c_hot { dest == 0; }
endclass


class Generator;
  mailbox #(Packet) gen2drv;
  mailbox #(Packet) gen2scb;
  mailbox #(Packet) gen2cov;
  int num_pkts = 100;
  int mode     = 0;
  int tag_cnt  = 0;

  function new();
    gen2drv = new(256);
    gen2scb = new(256);
    gen2cov = new(256);
  endfunction

  task run();
    for (int n = 0; n < num_pkts; n++) begin
      Packet p;
      if (mode == 1) begin
        HotspotPacket h = new();
        assert (h.randomize()) else $fatal(1, "hotspot randomize failed");
        h.tag = tag_cnt++;
        p = h;
      end else begin
        p = new();
        if (mode == 2) begin
          assert (p.randomize() with { dest == 2; len inside {[4:10]}; })
          else $fatal(1, "a2o randomize failed");
        end else if (mode == 3) begin
          assert (p.randomize() with { len == 1; })
          else $fatal(1, "single randomize failed");
        end else if (mode == 4) begin
          assert (p.randomize() with { len inside {[6:10]}; })
          else $fatal(1, "stress randomize failed");
        end else begin
          assert (p.randomize()) else $fatal(1, "randomize failed");
        end
        p.tag = tag_cnt++;
      end
      p.vc   = p.vc % NVC;
      p.src  = p.src % NPORTS;
      p.dest = p.dest % NPORTS;
      if (p.dest == p.src) p.dest = (p.dest + 1) % NPORTS;
      gen2drv.put(p);
      gen2scb.put(p);
      gen2cov.put(p);
    end
  endtask
endclass


class Driver;
  virtual router_if vif;
  mailbox #(Packet) gen2drv;
  int stall_pct        = 10;
  int test_ready_stall = 0;

  function new(virtual router_if vif, mailbox #(Packet) gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
  endfunction

  task reset_drive();
    vif.drv_cb.data_in  <= '{default:'0};
    vif.drv_cb.valid_in <= '{default:'0};
    vif.drv_cb.ready_in <= '{default:'1};
  endtask

  task drive_one(Packet p);
    logic [DATA_W-1:0] flits[$];
    flits.delete();
    if (p.len == 1) begin
      flits.push_back(mk_head(p.vc % NVC, p.dest, p.tag));
      flits[0][31:30] = F_SINGLE;
    end else begin
      flits.push_back(mk_head(p.vc % NVC, p.dest, p.tag));
      for (int i = 0; i < p.len - 2; i++)
        flits.push_back(mk_body(p.seed + i));
      flits.push_back(mk_tail(p.seed + p.len));
    end
    foreach (flits[i]) begin
      do begin
        @(vif.drv_cb);
      end while (vif.drv_cb.ready_out[p.src] !== 1'b1);
      vif.drv_cb.data_in[p.src]  <= flits[i];
      vif.drv_cb.valid_in[p.src] <= 1'b1;
      if (test_ready_stall && ($urandom_range(0, 99) < stall_pct)) begin
        vif.drv_cb.ready_in[p.dest] <= 1'b0;
      end else begin
        vif.drv_cb.ready_in <= '{default:'1};
      end
      @(vif.drv_cb);
      vif.drv_cb.valid_in[p.src] <= 1'b0;
      vif.drv_cb.data_in[p.src]  <= '0;
      vif.drv_cb.ready_in        <= '{default:'1};
    end
  endtask

  task run();
    Packet p;
    reset_drive();
    repeat (4) @(vif.drv_cb);
    forever begin
      gen2drv.get(p);
      drive_one(p);
    end
  endtask
endclass


class Monitor;
  virtual router_if  vif;
  mailbox #(ObsFlit) mon2scb;

  function new(virtual router_if vif, mailbox #(ObsFlit) mon2scb);
    this.vif     = vif;
    this.mon2scb = mon2scb;
  endfunction

  task run();
    repeat (4) @(vif.mon_cb);
    forever begin
      @(vif.mon_cb);
      for (int o = 0; o < NPORTS; o++) begin
        if (vif.mon_cb.valid_out[o] === 1'b1 && vif.mon_cb.ready_in[o] === 1'b1) begin
          ObsFlit f = new(o, vif.mon_cb.data_out[o]);
          mon2scb.put(f);
        end
      end
    end
  endtask
endclass


class Scoreboard;
  mailbox #(Packet)  exp_mb;
  mailbox #(ObsFlit) act_mb;
  Packet exp_by_tag[int];
  logic [DATA_W-1:0] cur_pkt[NPORTS][$];
  int exp_cnt = 0, got_pkt_cnt = 0, err_cnt = 0, got_flit_cnt = 0;

  function new(mailbox #(Packet) exp_mb, mailbox #(ObsFlit) act_mb);
    this.exp_mb = exp_mb;
    this.act_mb = act_mb;
  endfunction

  task collect_exp();
    Packet p;
    forever begin
      exp_mb.get(p);
      exp_by_tag[p.tag] = p;
      exp_cnt++;
    end
  endtask

  function int flit_tag(logic [DATA_W-1:0] head);
    return int'(head[26:3]);  // tag field, see mk_head
  endfunction

  task check();
    ObsFlit f;
    forever begin
      act_mb.get(f);
      got_flit_cnt++;
      cur_pkt[f.port].push_back(f.data);
      if (f.data[31:30] == 2'b10 || f.data[31:30] == 2'b11) begin
        logic [DATA_W-1:0] head;
        int tag;
        head = cur_pkt[f.port][0];
        tag  = int'(head[26:3]);
        if (int'(head[2:0]) % NPORTS != f.port) begin
          $display("[%0t][SCB-ERR] wrong dest: header dest=%0d ejected at %0d tag=%0d",
                   $time, int'(head[2:0]) % NPORTS, f.port, tag);
          err_cnt++;
        end
        if (exp_by_tag.exists(tag)) begin
          Packet exp;
          logic [DATA_W-1:0] exp_q[$];
          exp = exp_by_tag[tag];
          exp.get_flits(exp_q);
          if (exp_q.size() != cur_pkt[f.port].size()) begin
            $display("[%0t][SCB-ERR] len mismatch tag=%0d exp=%0d got=%0d",
                     $time, tag, exp_q.size(), cur_pkt[f.port].size());
            err_cnt++;
          end else begin
            for (int i = 0; i < exp_q.size(); i++) begin
              if (i == 0) begin
                if (exp_q[i][31:29] !== cur_pkt[f.port][i][31:29] ||
                    exp_q[i][2:0]  !== cur_pkt[f.port][i][2:0]) begin
                  $display("[%0t][SCB-ERR] header mismatch tag=%0d flit%0d",
                           $time, tag, i);
                  err_cnt++;
                end
              end else if (exp_q[i] !== cur_pkt[f.port][i]) begin
                $display("[%0t][SCB-ERR] payload mismatch tag=%0d flit%0d exp=%h got=%h",
                         $time, tag, i, exp_q[i], cur_pkt[f.port][i]);
                err_cnt++;
              end
            end
          end
          exp_by_tag.delete(tag);
        end else begin
          $display("[%0t][SCB-ERR] unknown tag %0d (may be header-tag packing)",
                   $time, tag);
          err_cnt++;
        end
        got_pkt_cnt++;
        cur_pkt[f.port].delete();
      end
    end
  endtask

  task run();
    fork
      collect_exp();
      check();
    join_none
  endtask

  function void report();
    $display("=== SCOREBOARD: exp=%0d got_pkts=%0d got_flits=%0d errors=%0d pending_exp=%0d ===",
             exp_cnt, got_pkt_cnt, got_flit_cnt, err_cnt, exp_by_tag.num());
  endfunction
endclass


class RouterCoverage;
  mailbox #(Packet) cov_mb;
  Packet pkt;
  covergroup cg;
    cp_src: coverpoint pkt.src {
      bins s[] = {[0:4]};
    }
    cp_dest: coverpoint pkt.dest {
      bins d[] = {[0:4]};
    }
    cp_vc: coverpoint pkt.vc {
      bins v[] = {[0:1]};
    }
    cp_len: coverpoint pkt.len {
      bins single = {1};
      bins short  = {[2:3]};
      bins med    = {[4:6]};
      bins long   = {[7:10]};
    }
    x_src_dest: cross cp_src, cp_dest;
    x_dest_vc:  cross cp_dest, cp_vc;
    x_dest_len: cross cp_dest, cp_len;
  endgroup

  function new(mailbox #(Packet) cov_mb);
    this.cov_mb = cov_mb;
    cg  = new();
    pkt = new();
  endfunction

  task run();
    Packet p;
    forever begin
      cov_mb.get(p);
      pkt = p;
      cg.sample();
    end
  endtask
endclass


class Env;
  virtual router_if vif;
  Generator      gen;
  Driver         drv;
  Monitor        mon;
  Scoreboard     scb;
  RouterCoverage cov;
  mailbox #(ObsFlit) mon2scb;

  function new(virtual router_if vif);
    this.vif = vif;
    gen      = new();
    mon2scb  = new(1024);
    drv      = new(vif, gen.gen2drv);
    mon      = new(vif, mon2scb);
    scb      = new(gen.gen2scb, mon2scb);
    cov      = new(gen.gen2cov);
  endfunction

  task run(int n, int mode, int stall);
    gen.num_pkts         = n;
    gen.mode             = mode;
    drv.test_ready_stall = stall;
    fork
      gen.run();
      drv.run();
      mon.run();
      scb.run();
      cov.run();
    join_none
  endtask
endclass


// +NUM=<pkts> +MODE=<0..4> +STALL=<0/1>
import router_pkg::*;

module top_tb;
  int NUM, MODE, STALL;

  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;

  router_if vif (.clk(clk), .rst_n(rst_n));

  noc_router dut (
    .clk(vif.clk), .rst_n(vif.rst_n),
    .data_in(vif.data_in), .valid_in(vif.valid_in), .ready_out(vif.ready_out),
    .data_out(vif.data_out), .valid_out(vif.valid_out), .ready_in(vif.ready_in)
  );

  Env env;

  initial begin
    if (!$value$plusargs("NUM=%d", NUM))     NUM   = 200;
    if (!$value$plusargs("MODE=%d", MODE))   MODE  = 0;
    if (!$value$plusargs("STALL=%d", STALL)) STALL = 0;
    $display("=== NoC CEP: NUM=%0d MODE=%0d STALL=%0d ===", NUM, MODE, STALL);
    $display("MODE: 0=random 1=hotspot(to 0) 2=all-to-one(to 2) 3=single-flit 4=long-stress");

    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;

    env = new(vif);
    env.run(NUM, MODE, STALL);

    repeat (NUM*25 + 2000) @(posedge clk);  // drain: ~25 cycles/packet

    env.scb.report();
    $display("=== COVERAGE: open Coverage tab (Riviera) for cg bins/x-src-dest ===");
    $display("=== TEST DONE ===");
    $finish;
  end

  initial begin
    #20ms;
    $display("TIMEOUT");
    $finish;
  end
endmodule

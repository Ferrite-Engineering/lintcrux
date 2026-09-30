-- LintCrux VHDL fixture — basic_warnings (GHDL engine).
--
-- A minimal VHDL design that produces well-known `--warn-*` findings:
--   * `--warn-hide`   — the process variable `hidden_var` shadows the
--                       architecture signal of the same name.
--   * `--warn-unused` — the shadowed signal `hidden_var` and the signal
--                       `unused_sig` are both declared and never read.
--
-- This design must ANALYSE CLEANLY. Until 2026-08-03 line 34 read
-- `q <= hidden_var(0);`, indexing an `integer` — a hard
-- "type of prefix is not an array" error that aborted the analysis. The
-- expected SARIF never mentioned it, because nothing had ever run GHDL
-- against this fixture. An error here is a fixture bug, not a finding.
--
-- expected.sarif.json is captured from a real `ghdl -a` run; see
-- capture.json in this directory for the binary and version.

library ieee;
use ieee.std_logic_1164.all;

entity design is
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    q   : out std_logic
  );
end entity design;

architecture rtl of design is
  signal hidden_var : std_logic := '0';
  signal unused_sig : std_logic := '0';
begin
  process (clk)
    variable hidden_var : integer := 0;  -- shadows the outer signal
  begin
    if rising_edge(clk) then
      if rst = '1' then
        hidden_var := 0;
        q <= '0';
      else
        hidden_var := hidden_var + 1;
        if hidden_var > 3 then
          q <= '1';
        else
          q <= '0';
        end if;
      end if;
    end if;
  end process;
end architecture rtl;

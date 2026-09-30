-- A deliberately imperfect saturating counter. Every finding below is
-- real; none of it is a syntax error, so the design analyses cleanly and
-- would simulate.
--
-- Do not "fix" these. The README explains what each one teaches.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  generic (
    WIDTH : integer := 8
  );
  port (
    clk   : in  std_logic;
    rst_n : in  std_logic;
    en    : in  std_logic;
    count : out std_logic_vector(WIDTH - 1 downto 0);
    tc    : out std_logic
  );
end entity counter;

architecture rtl of counter is

  -- Declared and never read anywhere. --warn-unused.
  signal spare_flag : std_logic := '0';

  -- This one looks used — the process below is full of `value`. It is
  -- not: the process variable declared below shadows it, so every
  -- one of those references is to the variable, and this signal is dead.
  -- That is the whole reason --warn-hide and --warn-unused are worth
  -- reading together, and why the report shows two findings here, not
  -- one.
  signal value      : unsigned(WIDTH - 1 downto 0) := (others => '0');

begin

  process (clk, rst_n)
    -- Shadows the architecture signal `value`. --warn-hide. Inside this
    -- process every mention of `value` means the variable, not the
    -- signal — which is exactly the confusion the warning exists for.
    variable value : integer := 0;
  begin
    if rst_n = '0' then
      value := 0;
    elsif rising_edge(clk) then
      if en = '1' then
        if value < 2 ** WIDTH - 1 then
          value := value + 1;
        end if;
      end if;
    end if;
    count <= std_logic_vector(to_unsigned(value, WIDTH));
    if value = 2 ** WIDTH - 1 then
      tc <= '1';
    else
      tc <= '0';
    end if;
  end process;

end architecture rtl;

#!/usr/bin/env python3
# Copyright 2026 Ferrite Engineering LLC
# SPDX-License-Identifier: Apache-2.0
"""Captures what nextpnr does with each pin-constraint fixture.

For every case under verification/fixtures/engines/constraints/captured/ it
synthesises top.v with Yosys, runs the family's nextpnr over the netlist and
the case's constraint file, and writes the result to the case's output.txt.

It writes output.txt and nothing else. The expected findings
(expected.sarif.json) are written by hand from the constraint files and are
never produced from this tool's output or from LintCrux's.

Usage:
    tool/capture_constraint_fixtures.py --suite <oss-cad-suite directory>
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "verification", "fixtures", "engines", "constraints", "captured",
)

# Family -> (Yosys synthesis command, nextpnr binary, device flags, how the
# constraint file is passed).
FAMILIES = {
    "ice40": (
        "synth_ice40 -top top -json netlist.json",
        "nextpnr-ice40",
        ["--up5k", "--package", "sg48"],
        "--pcf",
    ),
    "ecp5": (
        "synth_ecp5 -top top -json netlist.json",
        "nextpnr-ecp5",
        ["--25k", "--package", "CABGA256"],
        "--lpf",
    ),
    "gowin": (
        "synth_gowin -top top -json netlist.json",
        "nextpnr-himbaechel",
        ["--device", "GW1NR-LV9QN88PC6/I5", "--vopt", "family=GW1N-9"],
        "--vopt cst=",
    ),
}


def capture(case_dir, suite):
    name = os.path.basename(case_dir)
    family = name.split("_", 1)[0]
    synth, pnr, device, constraint_flag = FAMILIES[family]
    constraint = next(f for f in sorted(os.listdir(case_dir)) if f.startswith("pins."))
    bin_dir = os.path.join(suite, "bin")
    work = tempfile.mkdtemp(prefix="constraints-capture-")
    try:
        for f in ("top.v", constraint):
            shutil.copy(os.path.join(case_dir, f), work)
        env = dict(os.environ, HOME=work)
        subprocess.run(
            [os.path.join(bin_dir, "yosys"), "-q", "-p",
             f"read_verilog top.v; {synth}"],
            cwd=work, env=env, check=True,
        )
        if constraint_flag.endswith("="):
            flag, _, prefix = constraint_flag.partition(" ")
            constraint_args = [flag, prefix + constraint]
        else:
            constraint_args = [constraint_flag, constraint]
        cmd = [os.path.join(bin_dir, pnr), "-q", *device, *constraint_args,
               "--json", "netlist.json"]
        run = subprocess.run(cmd, cwd=work, env=env, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        shown = " ".join([pnr, "-q", *device, *constraint_args,
                          "--json", "netlist.json"])
        text = run.stdout.replace(work, "<work>")
        text = text.replace(os.path.expanduser("~"), "<home>")
        text = re.sub(r"/[^ \n]*oss-cad-suite[^ \n]*", "<suite>", text)
        with open(os.path.join(case_dir, "output.txt"), "w") as out:
            out.write(f"$ {shown}\n")
            out.write(text)
            if not text.endswith("\n"):
                out.write("\n")
            out.write(f"exit status: {run.returncode}\n")
        return run.returncode
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--suite", required=True,
                        help="OSS CAD Suite directory (the one holding bin/)")
    args = parser.parse_args()
    if not os.path.isdir(ROOT):
        sys.exit(f"missing fixture directory: {ROOT}")
    cases = sorted(d for d in os.listdir(ROOT)
                   if os.path.isdir(os.path.join(ROOT, d)))
    if not cases:
        sys.exit(f"no cases under {ROOT}")
    for case in cases:
        status = capture(os.path.join(ROOT, case), args.suite)
        print(f"{case}: nextpnr exit {status}")


if __name__ == "__main__":
    main()

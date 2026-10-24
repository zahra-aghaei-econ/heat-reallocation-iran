#!/usr/bin/env python3
"""
copy_to_paper.py
Copies the generated LaTeX fragments and figures of one run into the paper folder.

Usage (project root):
    python tools/copy_to_paper.py [RUN_NAME] [PAPER_FOLDER]

Defaults: RUN_NAME = run3_new_period_svc,
          PAPER_FOLDER = <project root>/paper
Copies  output/<RUN>/tex/*.tex      ->  <PAPER_FOLDER>/Tables/
        output/<RUN>/graphs/*.pdf   ->  <PAPER_FOLDER>/Figures/
(Existing files with the same name are overwritten. Nothing is deleted.)
Order to run everything: Stata (master.do) -> make_tex_tables.py -> make_tex_tables_b.py -> make_tex_tables_c.py -> make_tex_tables_d.py -> copy_to_paper.py
"""
import os
import sys
import shutil

RUN = sys.argv[1] if len(sys.argv) > 1 else "run3_new_period_svc"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAPER = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "paper")
OUT = os.path.join(ROOT, "output", RUN)

for sub, ext, dest in [("tex", ".tex", "Tables"), ("graphs", ".pdf", "Figures")]:
    src = os.path.join(OUT, sub)
    dst = os.path.join(PAPER, dest)
    os.makedirs(dst, exist_ok=True)
    n = 0
    if os.path.isdir(src):
        for f in sorted(os.listdir(src)):
            if f.endswith(ext):
                shutil.copy2(os.path.join(src, f), os.path.join(dst, f))
                n += 1
    print(f"{sub}: copied {n} files to {dst}")

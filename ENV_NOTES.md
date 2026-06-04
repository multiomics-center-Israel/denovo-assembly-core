# Environment rebuild notes (genome_assembly)

`requirements.txt` (pip) + `environment.yml` (conda) capture installed packages.
Manual, non-package changes that must be re-applied if the env is rebuilt:

1. **getAnnoFastaFromJoingenes.py Biopython fix** — `$CONDA_PREFIX/bin/getAnnoFastaFromJoingenes.py`
   line ~152: wrap in `Seq(...)`:  `record.seq = Seq(re.sub(regex, r'N', str(record.seq)))`
   (newer Biopython forbids assigning a plain str to record.seq; breaks BRAKER otherwise).
2. **GeneMark-ETP** (key-free) cloned to `<project>/tools/GeneMark-ETP`; driver exports
   GENEMARK_PATH/PROTHINT_PATH + bundled tools on PATH.
3. **Statistics::LineFit** perl module via `cpanm --notest Statistics::LineFit`.

#!/usr/bin/env bash
# Live monitor for the wasp annotation jobs. Run inside screen; Ctrl-C to quit the view
# (does NOT stop the jobs — they are detached).
P=/mnt/data/Projects/Elad_Chiel/wasp_genome_assembly
while true; do
  clear
  echo "===== WASP ANNOTATION MONITOR =====  $(date '+%F %T')"
  echo "(detach: Ctrl-A then D   |   this view is read-only, jobs keep running)"
  echo
  echo "--- JOBS ALIVE ---"
  pgrep -f run_resume_annotation.sh >/dev/null && echo "  resume driver (steps 1-4): RUNNING" || echo "  resume driver (steps 1-4): not running"
  pgrep -x tblastn >/dev/null && echo "  tblastn validation       : RUNNING" || echo "  tblastn validation       : done/idle"
  pgrep -x pblat   >/dev/null && echo "  pblat (BLAT TSA)         : RUNNING" || echo "  pblat (BLAT TSA)         : not running"
  pgrep -f "bin/hisat2" >/dev/null && echo "  hisat2 align (7.3)       : RUNNING"
  echo
  echo "--- RNA-Seq download (target _1=1075MB _2=1098MB) ---"
  ls -la "$P"/rnaseq/SRR1502981_*.fastq.gz 2>/dev/null | awk '{printf "  %-26s %.1f MB\n", $NF, $5/1048576}' || echo "  (not started)"
  echo
  echo "--- resume driver log (tail) ---"
  tail -n 8 "$P"/logs/resume_annotation_driver.log 2>/dev/null | sed 's/^/  /'
  echo
  echo "--- tblastn+BLAT driver log (tail) ---"
  tail -n 4 "$P"/logs/tblastn_blat_4980.log 2>/dev/null | sed 's/^/  /'
  sleep 15
done

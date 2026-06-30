#!/usr/bin/env bash
# P25_pasa_update — UPGRADE (never replace) the canonical annotation with the
# ALL-11 RNA-Seq evidence via PASA annotation-compare.
#
# What it does (ID-preserving, non-destructive):
#   1. transcript evidence = TSA (GBVV01) + ALL-11 StringTie transcripts
#      (gffread of merged_all11.gtf from E14 against the genome).
#   2. FRESH PASA sqlite (pasa_all11.sqlite) — does NOT reuse the stale June-11
#      venom-only DB that caused the de-novo fallback.
#   3. PASA alignAssembly (gmap, multi-CPU).
#   4. Load the canonical 16,820-gene models into the DB, then annotation-compare
#      (2 rounds) — this ADDS UTRs / refines splice structures on EXISTING loci.
#      annotation-compare runs at LOW CPU to avoid the SQLite "database is locked"
#      storm that --CPU 16 produced.
#   5. Output canonical_rna_updated.gff3 (~16,820 genes + UTR/isoform upgrades) and
#      its proteins. This is a CANDIDATE only — the canonical symlink is NOT touched
#      here (promotion is the human-gated Q43 step).
export PIPE_DOMAIN="annotation"; STEP_ID="P25_pasa_update"
source "$(dirname "$0")/_lib.sh"

ENV="genome_assembly"
GENOME="${PROJECT_ROOT}/final_assembly.fa"                                   # PASA reference (gmap-compatible names)
MERGED="${PROJECT_ROOT}/rnaseq/new/merged_all11.gtf"                         # E14 all-11 StringTie merge
TSA="${PROJECT_ROOT}/rnaseq/spalangia_tsa.fasta"                            # GBVV01 transcriptome
# BASE = braker_graft (17,541 genes = canonical 16,820 + 721 gated-novel BRAKER genes), so
# all-11 PASA adds UTRs/isoforms to the FULL gene set INCLUDING the new genes (which are
# currently CDS+exon only). Seqids MUST carry the _np1212 suffix to match the genome
# (final_assembly.fa); the .np1212 copy is the awk re-stamp of the bare-seqid graft GFF.
# Loading a bare-seqid GFF = zero transcript overlap = empty update (the 2026-06-17 failure).
CANON_GFF="${PROJECT_ROOT}/annotation/braker_graft/Spalangia_cameroni.braker_graft.np1212.gff3"
PASADIR="${PROJECT_ROOT}/analysis/utr/pasa_all11"                           # FRESH dir (not the venom-only one)
DB="${PASADIR}/pasa_all11.sqlite"
OUTDIR="${PROJECT_ROOT}/annotation/update_rna_all11"
OUT="${OUTDIR}/canonical_rna_updated.gff3"
OUTPROT="${OUTDIR}/canonical_rna_updated.proteins.fa"
ALN_CPU=12
# annotation-compare MUST be single-threaded: cDNA_annotation_comparer opens one
# shared SQLite DB; >1 worker collides on writes -> "database is locked" -> threads
# die and their contigs are SILENTLY DROPPED (this is exactly what wrecked the first
# run). --CPU 1 = one serialized connection = the lock is structurally impossible.
CMP_CPU=1

step_check() { [[ -s "$OUT" ]]; }

step_run() {
  for f in "$GENOME" "$MERGED" "$TSA" "$CANON_GFF"; do
    [[ -s "$f" ]] || { say "ERROR: required input missing: $f"; return 1; }
  done
  mkdir -p "$PASADIR" "$OUTDIR"

  # FORCE=1 => start from a clean DB so canonical loads into an empty store
  if [[ "${FORCE:-0}" == "1" ]]; then
    say "FORCE=1 — wiping prior pasa_all11 DB/state for a clean rebuild"
    rm -f "${DB}"* 2>/dev/null || true
    rm -rf "${PASADIR}/__pasa_${DB##*/}_SQLite_chkpts" 2>/dev/null || true
  fi

  # ---- STEP A: transcript evidence (TSA + all-11 StringTie) ----
  local TX="${PASADIR}/transcripts.fasta"
  local STG="${PASADIR}/all11_stringtie.fa"
  say "building transcript evidence: TSA + all-11 StringTie (merged_all11.gtf)"
  crun "$ENV" gffread -w "$STG" -g "$GENOME" "$MERGED" \
    || { say "ERROR: gffread of merged_all11.gtf failed"; return 1; }
  : > "$TX"
  cat "$TSA" >> "$TX"; say "+ TSA: $(grep -c '>' "$TSA") tx"
  cat "$STG" >> "$TX"; say "+ all-11 StringTie: $(grep -c '>' "$STG") tx"
  say "total transcript evidence: $(grep -c '>' "$TX") tx"
  ( cd "$PASADIR" && crun "$ENV" seqclean "$TX" >/dev/null 2>&1 || true )
  [[ -s "${TX}.clean" ]] || cp "$TX" "${TX}.clean"
  say "clean transcripts: $(grep -c '>' "${TX}.clean")"

  # ---- STEP B: PASA alignAssembly into a FRESH db ----
  local acfg="${PASADIR}/alignAssembly.config"
  { echo "DATABASE=${DB}"
    echo "validate_alignments_in_db.dbi:--MIN_PERCENT_ALIGNED=75"
    echo "validate_alignments_in_db.dbi:--MIN_AVG_PER_ID=90"
  } > "$acfg"
  if [[ -s "${DB}.pasa_assemblies.gff3" ]]; then
    say "PASA assemblies already present — skipping alignAssembly"
  else
    say "PASA alignAssembly (gmap, CPU=${ALN_CPU})"
    ( cd "$PASADIR" && crun "$ENV" Launch_PASA_pipeline.pl -c "$acfg" -C -R \
        -g "$GENOME" -t "${TX}.clean" --ALIGNERS gmap --CPU "$ALN_CPU" ) \
      || { say "ERROR: PASA alignAssembly failed"; return 1; }
  fi

  # ---- STEP C: load canonical models, then annotation-compare (UPGRADE) ----
  local ccfg="${PASADIR}/annotCompare.config"
  echo "DATABASE=${DB}" > "$ccfg"
  # PASAHOME: the helper *.dbi scripts (Load_Current_Gene_Annotations.dbi etc.) are
  # NOT on PATH — only Launch_PASA_pipeline.pl/pasa are symlinked into the env bin/.
  # The bin/ entry is a SYMLINK into opt/pasa-2.5.3, so `dirname dirname` of its
  # literal location yields the env root (no scripts/ there). Prefer the conda-
  # exported $PASAHOME; otherwise resolve the symlink with readlink -f.
  local PASAHOME LOADER
  PASAHOME=$(crun "$ENV" bash -c 'echo "${PASAHOME:-$(dirname "$(readlink -f "$(command -v Launch_PASA_pipeline.pl)")")}"')
  LOADER="${PASAHOME}/scripts/Load_Current_Gene_Annotations.dbi"
  [[ -s "$LOADER" ]] || { say "ERROR: PASA loader not found at ${LOADER} (PASAHOME=${PASAHOME})"; return 1; }
  say "loading canonical models into DB: ${CANON_GFF} (PASAHOME=${PASAHOME})"
  crun "$ENV" "$LOADER" \
      -c "$ccfg" -g "$GENOME" -P "$CANON_GFF" \
    || { say "ERROR: canonical load failed — refusing to fall back to de-novo"; return 1; }

  local round
  for round in 1 2; do
    say "annotation-compare round ${round} (CPU=${CMP_CPU}, lock-safe)"
    ( cd "$PASADIR" && crun "$ENV" Launch_PASA_pipeline.pl -c "$ccfg" -A \
        -g "$GENOME" -t "${TX}.clean" --CPU "$CMP_CPU" ) \
      || say "WARN: annotation-compare round ${round} returned nonzero (continuing)"
  done

  # ---- STEP D: harvest the upgraded GFF3 + proteins ----
  local UPD; UPD=$(ls -t "${PASADIR}"/*gene_structures_post_PASA_updates*.gff3 2>/dev/null | head -1)
  [[ -n "$UPD" && -s "$UPD" ]] || { say "ERROR: no PASA-updated GFF3 produced"; return 1; }
  cp "$UPD" "$OUT"
  crun "$ENV" gffread -y "$OUTPROT" -g "$GENOME" "$OUT" 2>/dev/null || say "WARN: protein extraction warn"
  local ngene nmrna
  ngene=$(awk -F'\t' '$3=="gene"' "$OUT" | wc -l)
  nmrna=$(awk -F'\t' '$3=="mRNA"' "$OUT" | wc -l)
  say "upgraded models: ${ngene} genes / ${nmrna} mRNA (canonical baseline 16820)"
  # Sanity gate: an UPGRADE keeps ~all 16,820 canonical loci. A big shortfall means
  # contigs were dropped (e.g. a lock storm) or canonical didn't load -> de-novo.
  # Fail loudly rather than promote a broken candidate.
  if [[ "$ngene" -lt 15000 ]]; then
    say "ERROR: only ${ngene} genes (<15000) — canonical was NOT preserved; refusing this candidate"
    return 1
  fi
  # Belt-and-suspenders: scan PASA logs for the lock signature, in case --CPU 1 ever changes
  if grep -rqi "database is locked" "${PASADIR}"/pasa_run.log.dir 2>/dev/null; then
    say "ERROR: SQLite 'database is locked' found in PASA logs — contigs may be dropped"
    return 1
  fi
  emit_report "$STEP_ID" "DONE" \
    "updated_gff3=${OUT}" "proteins=${OUTPROT}" \
    "genes=${ngene}" "mRNA=${nmrna}" "evidence=TSA+all11_stringtie" "db=${DB}"
  return 0
}
step_main "$@"

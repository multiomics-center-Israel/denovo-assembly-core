# Example: Spalangia cameroni assembly

This directory holds project-specific helpers used for the *S. cameroni* assembly run that
seeded `denovo-assembly-core`. They are **not** part of the generic pipeline — they reference
hardcoded plot filenames and PowerPoint templates from that specific project layout.

Treat them as a worked example of how to bolt one-off PPTX/HTML reporting onto the core
pipeline. Other projects can copy and adapt as needed.

## Files

- `project.yaml` — the configuration the wasp project actually uses; copy it into your
  project directory to reproduce the environment.
- `create_presentation.py` — builds the initial PPTX deck used by the pipeline as a template
  for `report.pptx_filename` updates.
- `add_qc_slides.py`, `add_genomescope_slides.py`, `add_coverage_slides.py` — append result
  slides to the deck after Phase 1 completes.
- `legacy_generate_report.py` (renamed from `generate_report.py`) — standalone HTML report
  generator for the *S. cameroni* run; superseded by `ReportGenerator` in
  `denovo_assembly_core.pipeline`, kept here for reference.

## Reproducing the run

```bash
cp examples/spalangia_cameroni/project.yaml /path/to/your/project/project.yaml
# Edit project.dir and input paths as needed.
bin/run_pipeline.sh --project-dir /path/to/your/project resume
```

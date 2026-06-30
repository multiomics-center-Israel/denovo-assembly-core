# NeatSeq-Flow versions of the pipelines

These YAMLs are **auto-generated** from the same `catalogue.tsv` that drives the bash
runners (`run_assembly_pipeline.sh`, `run_annotation_pipeline.sh`), so the two engines
cannot drift. Each step is a `Generic` module whose `script_path` invokes the **same
wrapper** the bash runner calls; `base:` edges encode the dependency DAG.

## Regenerate (never hand-edit the YAML)
```
python3 annotation/steps/gen_nsf.py --domain annotation \
    --catalogue annotation/steps/catalogue.tsv --out neatseq_flow/annotation_workflow.yaml
python3 annotation/steps/gen_nsf.py --domain assembly \
    --catalogue assembly/steps/catalogue.tsv   --out neatseq_flow/assembly_workflow.yaml
```

## Run (NeatSeq_Flow conda env, v1.6.0)
```
conda run -n NeatSeq_Flow neatseq_flow.py \
    -s neatseq_flow/sample_file.nsf \
    -p neatseq_flow/annotation_workflow.yaml \
    -d $PWD/neatseq_flow/wf_annotation
# then run a single step, a subtree, or all:
bash neatseq_flow/wf_annotation/scripts/<NN>.<step>/*.sh   # one step
bash neatseq_flow/wf_annotation/scripts/00.workflow.commands  # whole DAG
```

`Executor: Local` (bi-delllinux has no scheduler). To offload to zeus, switch
`Global_params.Executor` to `SGE` and add the qsub block.

## Relationship to the bash runners
Day-to-day use the bash runners — they add the `status` view, the CURRENT-NEXT pointer,
nohup/setsid detach, sequential chains for dependent LONG steps, and per-step `REPORT.md`
updates. The NeatSeq-Flow version is the portable/cluster-friendly export of the same DAG.

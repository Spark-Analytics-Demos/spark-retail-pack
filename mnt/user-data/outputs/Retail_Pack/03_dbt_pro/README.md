# spark_retail_pack_pro (Proprietary dbt Extensions)

> **Status:** Not yet developed. Awaiting completion of the open-source core.

This folder will hold the proprietary dbt project that extends the open-source core with licensed advanced functionality.

## What will go here

- `dbt_project.yml` declaring a dependency on `spark_retail_pack`
- Advanced metric models (LTV cohorts, RFM segmentation, marketing attribution)
- AI-ready layer (metric metadata, entity relationships, glossary embeddings input)
- Semantic layer YAML definitions (MetricFlow)
- Pro-only macros

## License

Will be released under a **commercial license**. Not open source. Source code distributed only to paying clients.

## Dependency

This package **requires** the open-source `spark_retail_pack` package to function. It does not work standalone.

## When to start building

After the open-source core is at least at v0.5 (functional but not yet polished). Building the pro extensions on top of an unstable core wastes effort.

## Reference

See `../01_design_docs/02_architecture.md` Section 2.4 for the planned folder structure and `../01_design_docs/11_open_source_vs_pro.md` (pending) for the exact open/pro split.

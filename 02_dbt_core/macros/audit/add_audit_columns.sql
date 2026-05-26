{% macro add_audit_columns(
    source_system,
    source_id_column,
    business_columns,
    extracted_at_column='_extracted_at',
    is_deleted_column=none
) %}
    {#--
        Emits the 8-column audit and lineage footer required on every staging,
        intermediate, core, and mart model. No model manages these columns
        individually — this macro guarantees consistency.

        Call at the END of the SELECT, after a trailing comma on the last
        business column. The macro emits comma-separated columns with NO
        leading or trailing comma.

        Pre-conditions (the calling model's CTE must already have):
          - extracted_at_column: the ingestion tool's sync timestamp, aliased
            in the staging CTE (e.g., _fivetran_synced AS _extracted_at)
          - is_deleted_column: a boolean expression for soft-delete state
            (or leave as none → always FALSE)

        Parameters:
          source_system        VARCHAR literal: 'shopify', 'stripe', etc.
          source_id_column     SQL expression for the natural/source record key
          business_columns     List of column names to hash for _record_hash
          extracted_at_column  Column already in scope holding extraction time
          is_deleted_column    SQL expression for soft-delete (none → false)

        Usage:
            select
                order_id,
                gross_amount,   -- note trailing comma
                {{ add_audit_columns(
                    source_system='shopify',
                    source_id_column='order_id',
                    business_columns=['order_id'],
                    extracted_at_column='_extracted_at'
                ) }}
            from renamed

        Section 4 Part 1 §4.2, Section 4 Part 2 §4.31
    --#}
    '{{ source_system }}'                                        as _source_system,
    cast({{ source_id_column }} as varchar)                      as _source_record_id,
    cast({{ extracted_at_column }} as timestamp_tz)              as _extracted_at,
    current_timestamp()                                          as _loaded_at,
    '{{ invocation_id }}'                                        as _dbt_invocation_id,
    '{{ this.name }}'                                            as _dbt_model,
    {{ dbt_utils.generate_surrogate_key(business_columns) }}     as _record_hash,
    coalesce(
        {{ is_deleted_column if is_deleted_column else 'false' }},
        false
    )                                                            as _is_deleted_at_source
{% endmacro %}

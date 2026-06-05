{{ config(materialized='table') }}

-- Payment method type dimension from Stripe per §4.8.
-- Grain is one row per payment method TYPE (e.g., card_visa_credit, wallet_applepay),
-- not per individual Stripe payment method instance. Deduplicates observed types from
-- stg_stripe__payment_methods and derives canonical identifiers.

with instances as (
    select distinct
        lower(coalesce(cast(payment_method_type as varchar), 'unknown'))  as raw_type,
        lower(coalesce(cast(card_brand          as varchar), ''))         as card_brand,
        lower(coalesce(cast(card_funding        as varchar), ''))         as card_funding,
        lower(coalesce(cast(card_wallet         as varchar), ''))         as card_wallet
    from {{ ref('stg_stripe__payment_methods') }}
),

typed as (
    select
        raw_type,
        card_wallet,

        -- canonical payment_method_id
        case
            when raw_type = 'card' and card_wallet != ''
                then 'wallet_' || replace(card_wallet, '_pay', 'pay')
            when raw_type = 'card' and card_brand != ''
                then 'card_' || card_brand || '_' || coalesce(nullif(card_funding, ''), 'unknown')
            when raw_type = 'card'
                then 'card_unknown'
            when raw_type in ('klarna')
                then 'bnpl_klarna'
            when raw_type in ('afterpay_clearpay')
                then 'bnpl_afterpay'
            when raw_type in ('affirm')
                then 'bnpl_affirm'
            when raw_type in ('zip')
                then 'bnpl_zip'
            when raw_type in ('us_bank_account', 'ach_debit')
                then 'bank_transfer_ach'
            when raw_type in ('sepa_debit')
                then 'bank_transfer_sepa'
            when raw_type in ('bacs_debit')
                then 'bank_transfer_bacs'
            when raw_type in ('au_becs_debit')
                then 'bank_transfer_becs'
            when raw_type = 'link'
                then 'wallet_link'
            else 'other_' || raw_type
        end                                                                as payment_method_id,

        -- canonical type (maps Stripe types to pack type vocabulary)
        case
            when raw_type = 'card' and card_wallet != ''    then 'digital_wallet'
            when raw_type = 'card'                          then 'card'
            when raw_type in ('klarna', 'afterpay_clearpay', 'affirm', 'zip', 'laybuy')
                                                            then 'bnpl'
            when raw_type in ('us_bank_account', 'ach_debit', 'sepa_debit',
                              'bacs_debit', 'au_becs_debit')
                                                            then 'bank_transfer'
            when raw_type = 'link'                          then 'digital_wallet'
            when raw_type = 'gift_card'                     then 'gift_card'
            when raw_type = 'cash'                          then 'cash'
            else 'other'
        end                                                                as payment_method_type,

        -- payment_provider
        case
            when card_wallet = 'apple_pay'                  then 'applepay'
            when card_wallet = 'google_pay'                 then 'googlepay'
            when card_wallet = 'samsung_pay'                then 'samsungpay'
            when card_wallet = 'link'                       then 'link'
            when raw_type = 'card' and card_brand != ''     then card_brand
            when raw_type = 'link'                          then 'link'
            when raw_type in ('klarna', 'afterpay_clearpay', 'affirm', 'zip')
                                                            then raw_type
            else raw_type
        end                                                                as payment_provider,

        nullif(card_brand, '')                                             as card_brand,
        nullif(card_funding, '')                                           as card_funding,

        current_timestamp()                                                as _extracted_at
    from instances
)

select
    {{ generate_dim_sk(['payment_method_id']) }}    as payment_method_sk,
    payment_method_id,

    -- display name (e.g. "Visa Credit Card", "Apple Pay")
    case
        when payment_method_type = 'card' and card_brand is not null and card_funding is not null
            then initcap(card_brand) || ' ' || initcap(card_funding) || ' Card'
        when payment_method_type = 'card' and card_brand is not null
            then initcap(card_brand) || ' Card'
        when payment_method_type = 'digital_wallet' and card_wallet != ''
            then initcap(replace(nullif(card_wallet, ''), '_', ' '))
        when payment_method_type = 'bnpl'
            then initcap(payment_provider)
        when payment_method_type = 'bank_transfer'
            then 'Bank Transfer (' || upper(payment_provider) || ')'
        else initcap(replace(payment_method_id, '_', ' '))
    end                                                                    as payment_method_name,

    payment_method_type,
    payment_provider,
    card_brand,
    card_funding,
    (payment_method_type = 'card')                                         as is_credit_card,
    (payment_method_type = 'digital_wallet')                               as is_digital_wallet,
    (payment_method_type = 'bnpl')                                         as is_bnpl,
    -- recurring capability: cards and bank transfers support subscriptions; BNPL/wallets typically don't
    payment_method_type in ('card', 'bank_transfer')                       as is_recurring_capable,
    {{ add_audit_columns(
        source_system='stripe',
        source_id_column='payment_method_id',
        business_columns=['payment_method_id', 'payment_method_type'],
        extracted_at_column='_extracted_at'
    ) }}
from typed
-- Multiple instances rows can map to the same payment_method_id (e.g. two different
-- card brands both using Apple Pay both collapse to 'wallet_applepay'). Deduplicate
-- to one row per canonical type, preferring rows with more card detail.
qualify row_number() over (
    partition by payment_method_id
    order by card_brand nulls last, card_funding nulls last
) = 1

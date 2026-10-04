-- Migration appliquée sur le projet Supabase cloud : telima_08a_enum_purchase

alter type telima.wallet_tx_type add value if not exists 'purchase';

SELECT id, conversation_id, created_at, content_attributes, 
       COALESCE(content_attributes ->> 'bot_provider', '') as bot_provider_value,
       content_attributes ? 'bot_provider' as has_bot_provider_key
FROM messages 
WHERE id IN (108, 109, 110, 111);

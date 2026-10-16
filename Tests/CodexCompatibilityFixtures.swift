enum CodexCompatibilityFixtures {
    static let currentTurnContext =
        #"{"type":"turn_context","payload":{"model":"current-model"}}"#
    static let currentTokenCount =
        #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"cached_input_tokens":40,"cache_write_input_tokens":2,"output_tokens":100,"reasoning_output_tokens":1,"total_tokens":1000},"last_token_usage":{"input_tokens":30000,"cached_input_tokens":40,"cache_write_input_tokens":2,"output_tokens":4000,"reasoning_output_tokens":1,"total_tokens":34000},"model_context_window":100000},"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":50.0,"window_minutes":10080,"resets_at":2000003600}}}}"#
    static let legacyTokenCount =
        #"{"type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"cached_input_tokens":3,"output_tokens":5,"reasoning_output_tokens":1,"total_tokens":25},"last_token_usage":{"input_tokens":20,"cached_input_tokens":3,"output_tokens":5,"reasoning_output_tokens":1,"total_tokens":12025},"model_context_window":12080},"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_at":2000000000},"secondary":{"used_percent":44.0,"window_minutes":10080,"resets_at":2000003600}}}}"#
}

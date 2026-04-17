Discourse::Application.routes.append do
  put "/private-topics/topics/:topic_id/allowed-users" =>
        "discourse_private_topics/allowed_users#update"
  get "/private-topics/topics/:topic_id/access-history" =>
        "discourse_private_topics/allowed_users#history"
end

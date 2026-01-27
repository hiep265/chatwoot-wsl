json.payload do
  json.array! @responses do |response|
    json.id response.id
    json.question response.question
    json.answer response.answer
    json.status response.status

    if response.documentable
      json.documentable do
        json.type response.documentable_type

        case response.documentable_type
        when 'Captain::Document'
          json.id response.documentable.id
          json.external_link response.documentable.external_link
          json.name response.documentable.name
        when 'Conversation'
          json.id response.documentable.display_id
          json.display_id response.documentable.display_id
        when 'User'
          json.id response.documentable.id
          json.email response.documentable.email
          json.available_name response.documentable.available_name
        end
      end
    end

    if response.respond_to?(:neighbor_distance)
      json.neighbor_distance response.neighbor_distance
      json.similarity(1.0 - response.neighbor_distance.to_f)
    end
  end
end

json.meta do
  json.total_count @responses_count
end

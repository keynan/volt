require 'mongo'
require 'volt/models'

class StoreTasks < Volt::TaskHandler
  def initialize(channel = nil, dispatcher = nil)
    @channel = channel
    @dispatcher = dispatcher
  end

  def db
    @@db ||= Volt::DataStore.fetch
  end

  def load_model(collection, path, data)
    model_name = collection.singularize.camelize

    # Fetch the model
    collection = store.send(:"_#{path[-2]}")

    # See if the model has already been made
    model = collection.find_one(_id: data[:_id])

    # Otherwise assign to the collection
    model ||= collection

    # Create a buffer
    buffer = model.buffer

    # Assign the data
    buffer.attributes = data

    buffer
  end

  def save(collection, path, data)
    data = data.symbolize_keys
    model = nil
    Volt::Model.no_save do
      model = load_model(collection, path, data)
    end

    # On the backend, the promise is resolved before its returned, so we can
    # return from within it.
    #
    # Pass the channel as a thread-local so that we don't update the client
    # who sent the update.
    Thread.current['in_channel'] = @channel
    promise = model.save!.then do |result|
      next nil
    end

    Thread.current['in_channel'] = nil

    promise
  end

  def delete(collection, id)
    # Load the model, then call .destroy on it
    store.send(:"_#{collection}").find(_id: id).limit(1).then do |model|
      # model[0].destroy
      if model[0].can_delete?
        db[collection].remove('_id' => id)
      end

      QueryTasks.live_query_pool.updated_collection(collection, @channel)
    end
  end
end

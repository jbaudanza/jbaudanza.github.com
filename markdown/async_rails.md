# Handling requests asynchronously in Rails

<time datetime="2013-01-24" pubdate>Jan 25, 2013</time>
<a href="http://news.ycombinator.com/submit" class="hn-share-button">Vote on HN</a>

It is generally considered bad practice to block a web request handler on a
network request to a third party service. If that service should become slow or
unavailable, this can clog up all your web processes.

For example, say for some reason you have a Rails action that queries Facebook
for a user's full name.

```ruby
class FacebookNamesController < ApplicationController
  def show
    uri = URI.parse("http://graph.facebook.com/" + param[:facebook_uid])
    response = Net::HTTP.get(uri)
    session[:name] = JSON.parse(response)['name']
    render :text => "Hello #{session[:name]}"
  end
end
```

If you are using the [Thin webserver](http://code.macournoyer.com/thin/), you can rewrite this code asynchronously.

```ruby
class FacebookNamesController < ApplicationController
  def show
    uri = "http://graph.facebook.com/" + param[:facebook_uid]
    http = EM::HttpRequest.new(uri).get(uri)

    # This informs thin that the request will be handled asynchronously
    self.response_body = ''
    self.status = -1

    # Set a callback to finish the request when facebook returns the query.
    # In the meantime, this process is free to handle other requests.
    http.callback do
      # Oops.. this line won't have the effect we want because the Session
      # middleware has already run its course
      session[:name] = JSON.parse(response)['name']

      # We'd like to use something like `render :text` here, but we
      # can't because we are limited to the raw Rack API.
      env['async.callback'].call('200', {}, "Hello #{session[:name]}")
    end
  end
end
```

The disadvantage with this code is that we are interfacing directly with thin's
asychronous rack layer. Because of this, we are losing out on all the middleware
that Rails provides. Since the Rail's session is handled by middleware, we are
unable to store the user's name in it.

To get back the full Rail's functionality, we need to construct a new
rack application that is bundled with all the Rail's middleware.

I've included that functionality into the following mixin module.

```ruby
module AsyncController
  # This is the rack endpoint that will be invoked asyncronously. It will be
  # wrapped in all the middleware that a normal Rails endpoint would have.
  class RackEndpoint
    attr_accessor :action

    def call(env)
      @action.call(env)
    end
  end

  @@endpoint = RackEndpoint.new

  def self.included(mod)
    # LocalCache isn't able to be instantiated twice, so it must be removed
    # from the new middleware stack.
    middlewares = Rails.application.middleware.middlewares.reject do |m|
      m.klass.name == "ActiveSupport::Cache::Strategy::LocalCache"
    end

    @@wrapped_endpoint = middlewares.reverse.inject(@@endpoint) do |a, e|
      e.build(a)
    end
  end

  # Called to finish an asynchronous request. Can be invoked with a block
  # or with the symbol of an action name.
  def finish_request(action_name=nil, &proc)
    async_callback = request.env.delete('async.callback')
    env = request.env.clone

    if !action_name
      env['async_controller.proc'] = proc
      action_name = :_async_action
    end

    @@endpoint.action = self.class.action(action_name)

    async_callback.call(@@wrapped_endpoint.call(env))
  end

  def _async_action
    instance_eval(&request.env['async_controller.proc'])
  end
end
```

With this mixin, our controller can be written like so:

```ruby
class FacebookNamesController < ApplicationController
  include AsyncController

  def show
    uri = "http://graph.facebook.com/" + param[:facebook_uid]
    http = EM::HttpRequest.new(uri).get(uri)

    http.callback do
      finish_async_request do
        session[:name] = JSON.parse(response)['name']
        render :text => "Hello #{session[:name]}"
      end
    end

    self.response_body = ''
    self.status = -1
  end
end
```

This give us access to the full functionality of Rails without having to
block waiting on an external service.

# Handling requests asynchronously in Rails

<time datetime="2012-11-25" pubdate>Nov 25, 2012</time>
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

    # Set a callback to finish the request when facebook returns the query.
    # In the meantime, this process is free to handle other requests.
    http.callback do
      # Oops.. this won't work.
      session[:name] = JSON.parse(response)['name']
      env['async.callback'].call('200', {}, "Hello #{session[:name]}")
    end

    # This informs thin that the request will be handled asynchronously
    throw :async
  end
end
```

The disadvantage with this code is that we are interfacing directly with thin's
asychronous rack layer. Because of this, we are losing out on all the middleware
that Rails provides. Since the Rail's session is handled by middleware, we are
unable to store the user's name in it.

To get back the full Rail's functionality, we need to construct a new
rack application that is bundled with all the Rail's middleware.

I've put included that functionality into the following mixin module.

```ruby
module AsyncController
  def self.included(mod)
    @@app ||= begin
      Rails.application.middleware.build(@@middleware)
    end
  end

  def finish_async_request(action_name=nil, &proc)
    if !action_name
      env['async_controller.proc'] = proc
      action_name = :_async_action
    end

    @@middleware.action = self.class.action(action_name)

    env['async.callback'].call(@@app.call(env))
  end

  class Middleware
    attr_accessor :action

    def call(env)
      @action.call(env)
    end
  end

  @@middleware = Middleware.new

  def _async_action
    env['async_controller.proc'].call(self)
  end
end
```

With this module, our controller can be written like so:

```ruby
class FacebookNamesController < ApplicationController
  include AsyncController

  def show
    uri = "http://graph.facebook.com/" + param[:facebook_uid]
    http = EM::HttpRequest.new(uri).get(uri)

    http.callback do
      finish_async_request do |controller|
        controller.session[:name] = JSON.parse(response)['name']
        controller.render :text => "Hello #{session[:name]}"
      end
    end

    throw :async
  end
end
```

This allows us the full functionality of Rails without having to block waiting
on an external service.

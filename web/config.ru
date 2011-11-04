# See site.defaults.yml for configuration.

require './sandbox_app'

app = SandboxApp.new

use Rack::CommonLogger
run app


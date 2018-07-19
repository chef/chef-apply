#
# Copyright:: Copyright (c) 2017 Chef Software Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module ChefApply
  class Error < StandardError
    attr_reader :id, :params
    attr_accessor :show_stack, :show_log, :decorate
    def initialize(id, *params)
      @id = id
      @params = params || []
      @show_log = true
      @show_stack = true
      @decorate = true
    end
  end

  class ErrorNoLogs < Error
    def initialize(id, *params)
      super
      @show_log = false
      @show_stack = false
    end
  end

  class ErrorNoStack < Error
    def initialize(id, *params)
      super
      @show_log = true
      @show_stack = false
    end
  end

  class WrappedError < StandardError
    attr_accessor :target_host, :contained_exception
    def initialize(e, target_host)
      super(e.message)
      @contained_exception = e
      @target_host = target_host
    end
  end

  class MultiJobFailure < ErrorNoLogs
    attr_reader :jobs
    def initialize(jobs)
      super("CHEFMULTI001")
      @jobs = jobs
      @decorate = false
    end
  end

  # Provide a base type for internal usage errors that should not leak out
  # but may anyway.
  class APIError < Error
  end
end


module ChefApply
  module Errors
    # Provides mappings of common errors that we don't explicitly
    # handle, but can offer expanded help text around.
    class StandardErrorResolver
      def self.resolve_exception(exception)
        deps
        show_log = true
        show_stack = true
        case exception
        when OpenSSL::SSL::SSLError
          if exception.message =~ /SSL.*verify failed.*/
            id = "CHEFNET002"
            show_log = false
            show_stack = false
          end
        when SocketError then id = "CHEFNET001"; show_log = false; show_stack = false
        end
        if id.nil?
          exception
        else
          e = ChefApply::Error.new(id, exception.message)
          e.show_log = show_log
          e.show_stack = show_stack
          e
        end
      end

      def self.wrap_exception(original, target_host = nil)
        resolved_exception = resolve_exception(original)
        WrappedError.new(resolved_exception, target_host)
      end

      def self.unwrap_exception(wrapper)
        resolve_exception(wrapper.contained_exception)
      end

      def self.deps
        # Avoid loading additional includes until they're needed
        require "socket"
        require "openssl"
      end
    end
  end
end

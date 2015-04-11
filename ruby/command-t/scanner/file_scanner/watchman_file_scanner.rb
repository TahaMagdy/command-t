# Copyright 2014 Greg Hurrell. All rights reserved.
# Licensed under the terms of the BSD 2-clause license.

require 'pathname'
require 'socket'

module CommandT
  class Scanner
    class FileScanner
      # A FileScanner which delegates the heavy lifting to Watchman
      # (https://github.com/facebook/watchman); useful for very large hierarchies.
      #
      # Inherits from FindFileScanner so that it can fall back to it in the event
      # that Watchman isn't available or able to fulfil the request.
      class WatchmanFileScanner < FindFileScanner
        # Exception raised when Watchman is unavailable or unable to process the
        # requested path.
        WatchmanError = Class.new(::RuntimeError)

        def paths!
          raw_sockname = %x{watchman --output-encoding=bser get-sockname}
          raise WatchmanError, 'get-sockname failed' if !$?.exitstatus.zero?
          result = Watchman::Utils.load(raw_sockname)
          raise WatchmanError, result['error'] if result.has_key?('error')

          UNIXSocket.open(result['sockname']) do |socket|
            root = Pathname.new(@path).realpath.to_s
            roots = Watchman::Utils.query(['watch-list'], socket)['roots']
            if !roots.include?(root)
              # this path isn't being watched yet; try to set up watch
              result = Watchman::Utils.query(['watch', root], socket)

              # root_restrict_files setting may prevent Watchman from working
              # or enforce_root_files/root_files (>= version 3.1)
              raise WatchmanError, result['error'] if result.has_key?('error')
            end

            query = ['query', root, {
              'expression' => ['type', 'f'],
              'fields'     => ['name'],
            }]
            paths = Watchman::Utils.query(query, socket)

            # could return error if watch is removed
            raise WatchmanError, paths['error'] if paths.has_key?('error')

            paths['files']
          end
        rescue Errno::ENOENT, WatchmanError
          # watchman executable not present, or unable to fulfil request
          super
        end
      end # class WatchmanFileScanner
    end # class FileScanner
  end # class Scanner
end # module CommandT

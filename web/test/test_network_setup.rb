require 'process_user'
require 'tap_device'
require 'dnsmasq'
require 'squid'

module TestNetworkSetup
  def with_network(tapdevs, &block)
    setup_network(tapdevs)
    begin
      block.call
    ensure
      teardown_network
    end
  end

  def setup_network(tapdevs)
    tapdevs = [tapdevs] if !tapdevs.is_a?(Enumerable)
    @tapdevs = tapdevs

    was_root = ProcessUser.is_root?
    ProcessUser.become_root!

    begin
      tapdevs.each {|tapdev| tapdev.create if !tapdev.exist? }
      tapdevs.each {|tapdev| tapdev.up if !tapdev.up? }
      @dnsmasq_pid = Dnsmasq.start(tapdevs)
      @squid_pid = Squid.start(tapdevs)

      begin
        yield if block_given?
      rescue Exception
        ProcessUser.become_root! # in case the block dropped root
        raise
      end
    rescue
      teardown_network
      raise
    ensure
      if was_root
        ProcessUser.become_root!
      else
        ProcessUser.drop_root!
      end
    end
  end

  def teardown_network
    if @tapdevs
      was_root = ProcessUser.is_root?
      ProcessUser.become_root!

      begin
        if @dnsmasq_pid
          Dnsmasq.stop(@dnsmasq_pid)
          @dnsmasq_pid = nil
        end
        if @squid_pid
          Squid.stop(@squid_pid)
          @squid_pid = nil
        end

        for tapdev in @tapdevs
          tapdev.down if tapdev.up?
          tapdev.destroy if tapdev.exist?
        end
        @tapdevs = nil
      ensure
        if was_root
          ProcessUser.become_root!
        else
          ProcessUser.drop_root!
        end
      end

    end
  end
end

require "test_helper"
require "json"
require "resolv"
require "net/http"
require "minitest/mock"

class SafeReferenceUrlTest < ActiveSupport::TestCase
  test "explicit local URL matrix preserves originals and rejects incompatible forms" do
    rows.each do |row|
      value = row.fetch("url").freeze
      if row.fetch("accepted")
        assert_same value, SafeReferenceUrl.call(value), row.fetch("id")
      else
        assert_nil SafeReferenceUrl.call(value), row.fetch("id")
      end
    end
  end

  test "non text and empty inputs are rejected without mutation" do
    [ nil, false, 42, {}, [], "", " " ].each { |value| assert_nil SafeReferenceUrl.call(value) }
  end

  test "validation never resolves names opens sockets or sends HTTP" do
    deny = ->(*) { flunk "URL validation attempted network access" }
    Resolv.stub(:getaddress, deny) do
      Resolv.stub(:getaddresses, deny) do
        Socket.stub(:getaddrinfo, deny) do
          TCPSocket.stub(:new, deny) do
            Net::HTTP.stub(:start, deny) do
              rows.each { |row| assert_equal row.fetch("accepted"), !!SafeReferenceUrl.call(row.fetch("url")), row.fetch("id") }
            end
          end
        end
      end
    end
  end

  private

  def rows
    JSON.parse(File.read(Rails.root.join("test/fixtures/files/reference_urls.json")))
  end
end

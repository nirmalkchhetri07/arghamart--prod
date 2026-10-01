# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Spree::Oauth::PendingToken do
  # The test env uses :null_store (writes always "succeed", reads always
  # miss), which would make the single-use marker unenforceable. Swap in a
  # real store for these examples.
  before do
    allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
  end

  def mint(purpose: described_class::EMAIL_MISSING)
    described_class.mint(
      purpose: purpose,
      identity: { provider: 'facebook', uid: 'fb-123', email: nil,
                  first_name: 'Ada', last_name: nil }
    )
  end

  it 'round-trips the identity payload' do
    token = mint

    payload = described_class.consume(token)

    expect(payload.slice('provider', 'uid', 'purpose')).to eq(
      'provider' => 'facebook', 'uid' => 'fb-123',
      'purpose' => described_class::EMAIL_MISSING
    )
  end

  it 'rejects a second consume of the same token' do
    token = mint

    described_class.consume(token)
    expect { described_class.consume(token) }.
      to raise_error(Spree::Oauth::InvalidToken, /already been used/)
  end

  it 'keeps the single-use marker beyond the token expiry' do
    token = mint

    expect(Rails.cache).to receive(:write).with(
      a_string_starting_with('oauth_pending_used:'), true,
      expires_in: described_class::MARKER_EXPIRY, unless_exist: true
    ).and_call_original

    described_class.consume(token)
  end

  it 'rejects an expired token' do
    payload = {
      'provider' => 'facebook', 'uid' => 'fb-123', 'email' => nil,
      'first_name' => nil, 'last_name' => nil,
      'purpose' => described_class::ACCOUNT_EXISTS, 'jti' => SecureRandom.hex(16)
    }
    expired = described_class.send(:verifier).
              generate(payload, expires_in: -1.second, purpose: described_class::PURPOSE)

    expect { described_class.consume(expired) }.
      to raise_error(Spree::Oauth::InvalidToken, /expired/)
  end

  it 'rejects a token with an unknown purpose' do
    payload = {
      'provider' => 'facebook', 'uid' => 'fb-123', 'email' => nil,
      'first_name' => nil, 'last_name' => nil,
      'purpose' => 'admin_backdoor', 'jti' => SecureRandom.hex(16)
    }
    forged = described_class.send(:verifier).
             generate(payload, expires_in: 10.minutes, purpose: described_class::PURPOSE)

    expect { described_class.consume(forged) }.
      to raise_error(Spree::Oauth::InvalidToken, /Unknown sign-in/)
  end

  it 'rejects garbage' do
    expect { described_class.consume('not-a-token') }.
      to raise_error(Spree::Oauth::InvalidToken)
  end
end

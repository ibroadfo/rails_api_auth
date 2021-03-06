describe 'Oauth2 API' do
  let!(:login) { create(:login) }

  describe 'POST /token' do
    let(:params) { { grant_type: 'password', username: login.identification, password: login.password } }

    subject { post '/token', params }

    context 'for grant_type "password"' do
      context 'with valid login credentials' do
        it 'responds with status 200' do
          subject

          expect(response).to have_http_status(200)
        end

        it 'responds with an access token' do
          subject

          expect(response.body).to be_json_eql({ access_token: login.oauth2_token }.to_json)
        end
      end

      context 'with invalid login credentials' do
        let(:params) { { grant_type: 'password', username: login.identification, password: 'badpassword' } }

        it 'responds with status 400' do
          subject

          expect(response).to have_http_status(400)
        end

        it 'responds with an invalid grant error' do
          subject

          expect(response.body).to be_json_eql({ error: 'invalid_grant' }.to_json)
        end
      end
    end

    context 'for grant_type "facebook_auth_code"' do
      include_context 'stubbed facebook requests'

      let(:params)                { { grant_type: 'facebook_auth_code', auth_code: 'authcode' } }
      let(:facebook_email)        { login.identification }
      let(:facebook_data) do
        {
          id:    '1238190321',
          email: facebook_email
        }
      end

      context 'when a login with for the Facebook account exists' do
        it 'connects the login to the Facebook account' do
          subject

          expect(login.reload.uid).to eq(facebook_data[:id])
        end

        it 'responds with status 200' do
          subject

          expect(response).to have_http_status(200)
        end

        it "responds with the login's OAuth 2.0 token" do
          subject

          expect(response.body).to be_json_eql({ access_token: login.oauth2_token }.to_json)
        end
      end

      context 'when no login for the Facebook account exists' do
        let(:facebook_email) { Faker::Internet.email }

        it 'responds with status 200' do
          subject

          expect(response).to have_http_status(200)
        end

        it 'creates a login for the Facebook account' do
          expect { subject }.to change { Login.where(identification: facebook_email).count }.by(1)
        end

        it "responds with the login's OAuth 2.0 token" do
          subject
          login = Login.where(identification: facebook_email).first

          expect(response.body).to be_json_eql({ access_token: login.oauth2_token }.to_json)
        end
      end

      context 'when no Facebook auth code is sent' do
        let(:params) { { grant_type: 'facebook_auth_code' } }

        it 'responds with status 400' do
          subject

          expect(response).to have_http_status(400)
        end

        it 'responds with a "no_authorization_code" error' do
          subject

          expect(response.body).to be_json_eql({ error: 'no_authorization_code' }.to_json)
        end
      end

      context 'when Facebook responds with an error' do
        before do
          stub_request(:get, FacebookAuthenticator::PROFILE_URL % { access_token: access_token }).to_return(status: 422)
        end

        it 'responds with status 502' do
          subject

          expect(response).to have_http_status(502)
        end

        it 'responds with an empty response body' do
          subject

          expect(response.body.strip).to eql('')
        end
      end
    end

    context 'for grant_type "google_auth_code"' do
      include_context 'stubbed google requests'

      let(:params) { { grant_type: 'google_auth_code', auth_code: 'authcode' } }
      let(:email) { login.identification }
      let(:google_data) do
        {
          sub: '1238190321',
          email: email
        }
      end

      context 'when a login with email for the Google account exists' do
        it 'connects the login to the Google account' do
          subject

          expect(login.reload.uid).to eq(google_data[:sub])
        end

        it 'responds with status 200' do
          subject

          expect(response).to have_http_status(200)
        end

        it "responds with the login's OAuth 2.0 token" do
          subject

          expect(response.body).to be_json_eql({ access_token: login.oauth2_token }.to_json)
        end
      end

      context 'when no login for the Google account exists' do
        let(:email) { Faker::Internet.email }

        it 'responds with status 200' do
          subject

          expect(response).to have_http_status(200)
        end

        it 'creates a login for the Gmail account' do
          expect { subject }.to change { Login.where(identification: email).count }.by(1)
        end

        it "responds with the login's OAuth 2.0 token" do
          subject
          login = Login.where(identification: email).first

          expect(response.body).to be_json_eql({ access_token: login.oauth2_token }.to_json)
        end
      end

      context 'when no Google auth code is sent' do
        let(:params) { { grant_type: 'google_auth_code' } }

        it 'responds with status 400' do
          subject

          expect(response).to have_http_status(400)
        end

        it 'responds with a "no_authorization_code" error' do
          subject

          expect(response.body).to be_json_eql({ error: 'no_authorization_code' }.to_json)
        end
      end

      context 'when Google responds with an error' do
        before do
          stub_request(:get, GoogleAuthenticator::PROFILE_URL % { access_token: 'access_token' }).to_return(status: 422)
        end

        it 'responds with status 502' do
          subject

          expect(response).to have_http_status(502)
        end

        it 'responds with an empty response body' do
          subject

          expect(response.body.strip).to eql('')
        end
      end
    end

    context 'for an unknown grant type' do
      let(:params) { { grant_type: 'UNKNOWN' } }

      it 'responds with status 400' do
        subject

        expect(response).to have_http_status(400)
      end

      it 'responds with an "unsupported_grant_type" error' do
        subject

        expect(response.body).to be_json_eql({ error: 'unsupported_grant_type' }.to_json)
      end
    end
  end

  describe 'POST #destroy' do
    let(:params) { { token_type_hint: 'access_token', token: login.oauth2_token } }

    subject { post '/revoke', params }

    it 'responds with status 200' do
      subject

      expect(response).to have_http_status(200)
    end

    it "resets the login's OAuth 2.0 token" do
      expect { subject }.to change { login.reload.oauth2_token }

      subject
    end

    context 'for an invalid token' do
      let(:params) { { token_type_hint: 'access_token', token: 'badtoken' } }

      it 'responds with status 200' do
        subject

        expect(response).to have_http_status(200)
      end

      it "doesn't reset any logins' token" do
        expect_any_instance_of(LoginNotFound).to receive(:refresh_oauth2_token!)

        subject
      end
    end
  end
end

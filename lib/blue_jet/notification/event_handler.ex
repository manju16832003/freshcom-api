defmodule BlueJet.Notification.EventHandler do
  @behaviour BlueJet.EventHandler

  alias BlueJet.Repo
  alias BlueJet.GlobalMailer
  alias BlueJet.Notification.{Trigger, EmailTemplate, Email, SmsTemplate}

  # Creates the default email template and notification trigger for account when
  # an account is first created.
  def handle_event("identity.account.create.success", %{ account: account, test_account: test_account }) do
    # Live account
    email_template =
      account
      |> EmailTemplate.AccountDefault.password_reset()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_password_reset_email(email_template)
    |> Repo.insert!()

    email_template =
      account
      |> EmailTemplate.AccountDefault.password_reset_not_registered()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_password_reset_not_registered_email(email_template)
    |> Repo.insert!()

    email_template =
      account
      |> EmailTemplate.AccountDefault.email_confirmation()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_email_confirmation_email(email_template)
    |> Repo.insert!()

    email_template =
      account
      |> EmailTemplate.AccountDefault.order_confirmation()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_order_confirmation_email(email_template)
    |> Repo.insert!()

    sms_template =
      account
      |> SmsTemplate.AccountDefault.phone_verification_code()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_phone_verification_code_sms(sms_template)
    |> Repo.insert!()

    sms_template =
      account
      |> SmsTemplate.AccountDefault.tfa_code()
      |> Repo.insert!()
    account
    |> Trigger.AccountDefault.send_tfa_code_sms(sms_template)
    |> Repo.insert!()

    # Test account
    email_template =
      test_account
      |> EmailTemplate.AccountDefault.password_reset()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_password_reset_email(email_template)
    |> Repo.insert!()

    email_template =
      test_account
      |> EmailTemplate.AccountDefault.password_reset_not_registered()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_password_reset_not_registered_email(email_template)
    |> Repo.insert!()

    email_template =
      test_account
      |> EmailTemplate.AccountDefault.email_confirmation()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_email_confirmation_email(email_template)
    |> Repo.insert!()

    email_template =
      test_account
      |> EmailTemplate.AccountDefault.order_confirmation()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_order_confirmation_email(email_template)
    |> Repo.insert!()

    sms_template =
      test_account
      |> SmsTemplate.AccountDefault.phone_verification_code()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_phone_verification_code_sms(sms_template)
    |> Repo.insert!()

    sms_template =
      test_account
      |> SmsTemplate.AccountDefault.tfa_code()
      |> Repo.insert!()
    test_account
    |> Trigger.AccountDefault.send_tfa_code_sms(sms_template)
    |> Repo.insert!()

    {:ok, nil}
  end

  def handle_event("identity.email_confirmation_token.create.success", %{ user: %{ account_id: nil } }) do
    {:ok, nil}
  end

  def handle_event("identity.password_reset_token.create.success", %{ user: user = %{ account_id: nil } }) do
    Email.Factory.password_reset_email(user)
    |> GlobalMailer.deliver_later()

    {:ok, nil}
  end

  def handle_event("identity.password_reset_token.create.error.email_not_found", %{ email: email }) do
    Email.Factory.password_reset_not_registered_email(email)
    |> GlobalMailer.deliver_later()

    {:ok, nil}
  end

  # def handle_event("identity.phone_verification_code.create.success", %{ account: account, phone_verification_code: pvc }) do
  #   ExAws.SNS.publish("Your verification code is: #{pvc.value}", phone_number: pvc.phone_number)
  #   |> ExAws.request()

  #   {:ok, nil}
  # end

  # def handle_event("identity.user.tfa_code.create.success", %{ user: user }) do
  #   ExAws.SNS.publish("Your verification code is: #{user.tfa_code}", phone_number: user.phone_number)
  #   |> ExAws.request()

  #   {:ok, nil}
  # end

  def handle_event(event, data = %{ account: account }) when not is_nil(account) do
    triggers =
      Trigger.Query.default()
      |> Trigger.Query.for_account(account.id)
      |> Trigger.Query.filter_by(%{ event: event })
      |> Repo.all()

    Enum.each(triggers, fn(trigger) ->
      Trigger.fire_action(trigger, data)
    end)

    {:ok, nil}
  end

  def handle_event(_, _) do
    {:ok, nil}
  end
end
package EPrints::Plugin::Screen::EPrint::Staff::DataCiteREST;

@ISA = ( 'EPrints::Plugin::Screen::EPrint' );

use strict;
use warnings;


sub new
{
    my( $class, %params ) = @_;

    my $self =
        $class->SUPER::new( %params );

    #
    # No generic privilege such as admin/editor is sufficient.
    # Access is checked explicitly against datacitedoi.write_userids.
    #
    $self->{actions} = [
        qw/
            datacite_preflight
            datacite_prepare_draft
            datacite_create_draft
            datacite_cancel_draft
            datacite_prepare_publish
            datacite_publish_findable
            datacite_cancel_publish
            datacite_prepare_update_url
            datacite_update_url_https
            datacite_cancel_update_url
        /
    ];

    $self->{appears} = [
        {
            place    => "eprint_editor_actions",
            action   => "datacite_preflight",
            position => 1978,
        },
        {
            place    => "eprint_editor_actions",
            action   => "datacite_prepare_draft",
            position => 1979,
        },
        {
            place    => "eprint_editor_actions",
            action   => "datacite_prepare_publish",
            position => 1980,
        },
        {
            place    => "eprint_editor_actions",
            action   => "datacite_prepare_update_url",
            position => 1981,
        },
    ];

    return $self;
}


############################################################
# Current web user must be explicitly allowlisted.
############################################################

sub _current_user_allowed
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    return 0
        unless defined $repository;

    my $user =
        $repository->current_user();

    return 0
        unless defined $user;

    my $userid =
        $user->id;

    return 0
        unless defined $userid
        && $userid =~ /^[0-9]+$/;

    my $allowed =
        $repository->get_conf(
            "datacitedoi",
            "write_userids"
        );

    return 0
        unless ref( $allowed ) eq "HASH";

    return (
        exists $allowed->{$userid}
        && $allowed->{$userid}
    ) ? 1 : 0;
}


############################################################
# Global web-write gate.
#
# Fail closed:
#   - missing/false web_writes_enabled => read-only web Screen;
#   - true web_writes_enabled          => write actions may proceed,
#     but only for explicit write_userids and subject to the
#     independent Event hard gate.
############################################################

sub _web_writes_enabled
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    return 0
        unless defined $repository;

    return $repository->get_conf(
        "datacitedoi",
        "web_writes_enabled"
    ) ? 1 : 0;
}


############################################################
# Screen visibility.
############################################################

sub can_be_viewed
{
    my( $self ) = @_;

    return $self->_current_user_allowed();
}


############################################################
# Keep the normal EPrint view context.
############################################################

sub about_to_render
{
    my( $self ) = @_;

    $self->EPrints::Plugin::Screen::EPrint::View::about_to_render;
}


############################################################
# Permission for the read-only preflight action.
############################################################

sub allow_datacite_preflight
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for the Draft PREVIEW action.
#
# This action remains read-only.
############################################################

sub allow_datacite_prepare_draft
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# READ-ONLY Draft preview.
#
# IMPORTANT:
#   - verifies the same hard write gate;
#   - performs fresh authenticated DataCite preflight;
#   - prepares fresh XML and JSON Draft payload;
#   - performs NO POST/PUT/DELETE;
#   - performs NO EPrints modification;
#   - does NOT call create_mint_draft().
############################################################

sub action_datacite_prepare_draft
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    return undef
        unless defined $repository;

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless( defined $eprint )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: eprint not available."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Verify exactly the same web-user gate used by write methods.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $event->_write_authorised();

    unless( $write_ok )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST Draft preview: DENY; "
                . $write_reason
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Fresh authenticated preflight + fresh Draft payload.
    # prepare_mint_rest_payload performs NO write request.
    #
    my(
        $mode,
        $doi,
        $reason,
        $json,
        $xml,
        $landing_url
    ) =
        $event->prepare_mint_rest_payload(
            $eprint
        );

    my $title =
        $eprint->get_value( "title" )
        || "";

    my $xml_state =
        (
            defined $xml
            && $xml ne ""
        )
        ? "READY"
        : "NONE";

    my $payload_state =
        (
            defined $json
            && $json ne ""
        )
        ? "READY"
        : "NONE";

    my $text =
        "DataCite REST Draft preview; "
        . "write_gate=ALLOW; "
        . "userid=$acting_userid; "
        . "eprint=" . $eprint->id . "; "
        . "title=[$title]; "
        . "mode=$mode; "
        . "doi=[" . ($doi || "") . "]; "
        . "landing_url=[" . ($landing_url || "") . "]; "
        . "xml=$xml_state; "
        . "payload=$payload_state; "
        . "event=ABSENT_BY_INVARIANT; "
        . "WRITE=NO; "
        . "reason=$reason";

    unless( $mode eq "MINT_PAYLOAD_READY" )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text( $text )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Show the verified preview together with a SECOND,
    # explicit POST confirmation form.
    #
    # Merely rendering this form performs NO DataCite write.
    #
    my $frag =
        $session->make_doc_fragment;

    my $summary =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    $summary->appendChild(
        $session->make_text( $text )
    );

    #
    # Preview-only mode: the verified read-only result remains
    # visible, but no write confirmation form is rendered.
    #
    unless( $self->_web_writes_enabled() )
    {
        my $readonly_notice =
            $frag->appendChild(
                $session->make_element( "p" )
            );

        my $readonly_strong =
            $readonly_notice->appendChild(
                $session->make_element( "strong" )
            );

        $readonly_strong->appendChild(
            $session->make_text(
                "Web writes are disabled by configuration. "
                . "This verified preview is read-only; "
                . "no DataCite write action is available."
            )
        );

        $self->{processor}->add_message(
            "warning",
            $frag
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $warning =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    my $strong =
        $warning->appendChild(
            $session->make_element( "strong" )
        );

    $strong->appendChild(
        $session->make_text(
            "Nessun DOI è stato ancora creato. "
            . "Il pulsante seguente creerà esclusivamente "
            . "un record DataCite nello stato Draft."
        )
    );

    my $form =
        $frag->appendChild(
            $self->render_form(
                "datacite_draft_" . $eprint->id
            )
        );

    $form->appendChild(
        $session->render_action_buttons(
            datacite_create_draft =>
                $self->phrase(
                    "create_draft_button"
                ),
            datacite_cancel_draft =>
                $session->phrase(
                    "lib/submissionform:action_cancel"
                ),
            _order => [
                qw/
                    datacite_create_draft
                    datacite_cancel_draft
                /
            ],
        )
    );

    $self->{processor}->add_message(
        "warning",
        $frag
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}



############################################################
# Permission for URL-update preview.
############################################################

sub allow_datacite_prepare_update_url
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for explicit URL update.
############################################################

sub allow_datacite_update_url_https
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless $self->_web_writes_enabled();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for cancellation.
############################################################

sub allow_datacite_cancel_update_url
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# READ-ONLY preview for UPDATE_MODERN URL upgrade.
#
# Performs authenticated GET and semantic comparison only.
# NO PUT.
# NO POST.
# NO EPrints modification.
############################################################

sub action_datacite_prepare_update_url
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless(
        defined $repository
        && defined $session
        && defined $eprint
    )
    {
        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST "
                . "could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Same hard current-user gate used by write methods.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $event->_write_authorised();

    unless( $write_ok )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST URL-update preview: DENY; "
                . $write_reason
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Fresh authenticated GET + semantic comparison.
    # prepare_update_modern() performs NO write.
    #
    my(
        $mode,
        $doi,
        $reason,
        $remote
    ) =
        $event->prepare_update_modern(
            $eprint
        );

    if( $mode eq "UPDATE_NOOP" )
    {
        $self->{processor}->add_message(
            "message",
            $session->make_text(
                "DataCite REST URL-update preview; "
                . "write_gate=ALLOW; "
                . "userid=$acting_userid; "
                . "eprint=" . $eprint->id . "; "
                . "mode=UPDATE_NOOP; "
                . "doi=[" . ($doi || "") . "]; "
                . "reason=$reason; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    unless(
        $mode eq "UPDATE_URL_HTTPS_READY"
        && defined $remote
    )
    {
        my $different = "";

        if(
            defined $remote
            && ref(
                $remote->{_datacite_different_properties}
            ) eq "ARRAY"
        )
        {
            $different =
                join(
                    ",",
                    @{
                        $remote->{_datacite_different_properties}
                    }
                );
        }

        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST URL-update preview blocked; "
                . "write_gate=ALLOW; "
                . "userid=$acting_userid; "
                . "eprint=" . $eprint->id . "; "
                . "mode=$mode; "
                . "doi=[" . ($doi || "") . "]; "
                . "different_properties=[" . $different . "]; "
                . "reason=$reason; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $remote_url =
        $remote->{url}
        || "";

    my $local_url =
        $remote->{_datacite_local_url}
        || $eprint->url()
        || "";

    my $client =
        $remote->{_datacite_client_id}
        || "";

    my $state =
        $remote->{state}
        || "";

    my $metadata =
        $remote->{_datacite_metadata_compare}
        || "";

    my $text =
        "DataCite REST URL-update preview; "
        . "write_gate=ALLOW; "
        . "userid=$acting_userid; "
        . "eprint=" . $eprint->id . "; "
        . "mode=UPDATE_URL_HTTPS_READY; "
        . "doi=[" . ($doi || "") . "]; "
        . "state=[" . $state . "]; "
        . "client=[" . $client . "]; "
        . "metadata=[" . $metadata . "]; "
        . "remote_url=[" . $remote_url . "]; "
        . "local_url=[" . $local_url . "]; "
        . "WRITE=NO";

    my $frag =
        $session->make_doc_fragment;

    my $summary =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    $summary->appendChild(
        $session->make_text( $text )
    );

    #
    # Preview-only mode: the verified read-only result remains
    # visible, but no write confirmation form is rendered.
    #
    unless( $self->_web_writes_enabled() )
    {
        my $readonly_notice =
            $frag->appendChild(
                $session->make_element( "p" )
            );

        my $readonly_strong =
            $readonly_notice->appendChild(
                $session->make_element( "strong" )
            );

        $readonly_strong->appendChild(
            $session->make_text(
                "Web writes are disabled by configuration. "
                . "This verified preview is read-only; "
                . "no DataCite write action is available."
            )
        );

        $self->{processor}->add_message(
            "warning",
            $frag
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $warning =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    my $strong =
        $warning->appendChild(
            $session->make_element( "strong" )
        );

    $strong->appendChild(
        $session->make_text(
            "I metadati DataCite sono identici. "
            . "Il pulsante seguente aggiornerà esclusivamente "
            . "il landing URL da HTTP a HTTPS. "
            . "Nessun metadato XML sarà inviato."
        )
    );

    my $form =
        $frag->appendChild(
            $self->render_form(
                "datacite_update_url_" . $eprint->id
            )
        );

    $form->appendChild(
        $session->render_action_buttons(
            datacite_update_url_https =>
                $self->phrase(
                    "update_url_https_button"
                ),
            datacite_cancel_update_url =>
                $session->phrase(
                    "lib/submissionform:action_cancel"
                ),
            _order => [
                qw/
                    datacite_update_url_https
                    datacite_cancel_update_url
                /
            ],
        )
    );

    $self->{processor}->add_message(
        "warning",
        $frag
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# Cancel URL update.
#
# NO DataCite operation.
############################################################

sub action_datacite_cancel_update_url
{
    my( $self ) = @_;

    $self->{processor}->add_message(
        "message",
        $self->{session}->make_text(
            "DataCite URL update cancelled. "
            . "No DOI or metadata were modified."
        )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# UPDATE DATACITE LANDING URL HTTP -> HTTPS.
#
# THIS IS A WRITE ACTION.
#
# The Event method independently repeats every safety check
# immediately before its single PUT.
############################################################

sub action_datacite_update_url_https
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless(
        defined $repository
        && defined $session
        && defined $eprint
    )
    {
        return undef;
    }

    unless(
           $self->_current_user_allowed()
        && $self->_web_writes_enabled()
    )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST web write denied by Screen policy."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST "
                . "could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my(
        $mode,
        $doi,
        $reason,
        $remote
    ) =
        $event->update_modern_url_https(
            $eprint,
            undef,
            undef,
            "UPDATE_URL_HTTPS"
        );

    my $text =
        "DataCite REST URL-update result; "
        . "mode=$mode; "
        . "eprint=" . $eprint->id . "; "
        . "doi=[" . ($doi || "") . "]; "
        . "reason=$reason";

    if( defined $remote )
    {
        $text .=
            "; state=["
            . ($remote->{state} || "")
            . "]"
            . "; client=["
            . ($remote->{_datacite_client_id} || "")
            . "]"
            . "; remote_url=["
            . ($remote->{url} || "")
            . "]"
            . "; local_url=["
            . ($remote->{_datacite_local_url} || $eprint->url() || "")
            . "]"
            . "; metadata=["
            . ($remote->{_datacite_metadata_compare} || "")
            . "]";
    }

    my $message_type;

    if(
        $mode eq "UPDATE_URL_HTTPS_DONE"
    )
    {
        $message_type = "message";
    }
    elsif(
           $mode =~ /^UPDATE_SENT_/
        || $mode eq "UPDATE_NOT_CONFIRMED"
        || $mode eq "UPDATE_URL_APPLIED_FINAL_COMPARE_FAILED"
    )
    {
        $message_type = "warning";
    }
    else
    {
        $message_type = "error";
    }

    $self->{processor}->add_message(
        $message_type,
        $session->make_text( $text )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# Permission for Findable preview.
############################################################

sub allow_datacite_prepare_publish
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for explicit Findable publication.
############################################################

sub allow_datacite_publish_findable
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless $self->_web_writes_enabled();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for cancellation.
############################################################

sub allow_datacite_cancel_publish
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# READ-ONLY preview for Draft -> Findable.
#
# NO PUT.
# NO EPrints modification.
############################################################

sub action_datacite_prepare_publish
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless(
        defined $repository
        && defined $session
        && defined $eprint
    )
    {
        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST "
                . "could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Verify the same current-user hard gate.
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $event->_write_authorised();

    unless( $write_ok )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST Publish preview: DENY; "
                . $write_reason
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Credentials are needed only for authenticated GET.
    #
    my(
        $username,
        $password,
        $credential_error
    ) =
        $event->_datacite_credentials();

    unless( defined $username )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST Publish preview: "
                . (
                    $credential_error
                    || "credentials unavailable"
                  )
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Local item must still have no managed DOI and remain
    # a valid mint candidate.
    #
    my(
        $local_mode,
        $doi,
        $local_reason
    ) =
        $event->classify_datacite(
            $eprint
        );

    unless( $local_mode eq "MINT" )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked; "
                . "local_mode=$local_mode; "
                . "doi=[" . ($doi || "") . "]; "
                . "reason=$local_reason; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $local_doi =
        $eprint->get_value( "doi" )
        || "";

    if( $local_doi ne "" )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked: "
                . "local doi field is already populated; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $landing_url =
        $eprint->url();

    my(
        $http_code,
        $remote,
        $http_reason
    ) =
        $event->_datacite_member_get(
            $doi,
            $username,
            $password
        );

    unless(
        defined $http_code
        && $http_code == 200
        && defined $remote
    )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked; "
                . "doi=[" . ($doi || "") . "]; "
                . "remote_http=["
                . (
                    defined $http_code
                    ? $http_code
                    : ""
                  )
                . "]; reason="
                . (
                    $http_reason
                    || "remote DOI unavailable"
                  )
                . "; WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my(
        $identity_ok,
        $identity_reason
    ) =
        $event->_verify_remote_identity(
            $doi,
            $remote
        );

    unless( $identity_ok )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked; "
                . $identity_reason
                . "; WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $remote_url =
        $remote->{url}
        || "";

    unless(
        defined $landing_url
        && $landing_url ne ""
        && $remote_url eq $landing_url
    )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked; "
                . "remote landing URL differs from EPrint URL; "
                . "remote_url=[" . $remote_url . "]; "
                . "local_url=[" . ($landing_url || "") . "]; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $state =
        lc(
            $remote->{state}
            || ""
        );

    unless(
        $state eq "draft"
        || $state eq "findable"
    )
    {
        $self->{processor}->add_message(
            "warning",
            $session->make_text(
                "DataCite REST Publish preview blocked; "
                . "remote state=["
                . (
                    $remote->{state}
                    || ""
                  )
                . "]; expected Draft or Findable; "
                . "WRITE=NO"
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $client =
        $remote->{_datacite_client_id}
        || "";

    my $preview_mode =
        $state eq "draft"
        ? "PUBLISH_READY"
        : "RECONCILE_READY";

    my $text =
        "DataCite REST Publish preview; "
        . "write_gate=ALLOW; "
        . "userid=$acting_userid; "
        . "eprint=" . $eprint->id . "; "
        . "mode=$preview_mode; "
        . "doi=[" . ($doi || "") . "]; "
        . "state=[" . ($remote->{state} || "") . "]; "
        . "client=[" . $client . "]; "
        . "landing_url=[" . $remote_url . "]; "
        . "local_doi=[]; "
        . "WRITE=NO";

    my $frag =
        $session->make_doc_fragment;

    my $summary =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    $summary->appendChild(
        $session->make_text( $text )
    );

    #
    # Preview-only mode: the verified read-only result remains
    # visible, but no write confirmation form is rendered.
    #
    unless( $self->_web_writes_enabled() )
    {
        my $readonly_notice =
            $frag->appendChild(
                $session->make_element( "p" )
            );

        my $readonly_strong =
            $readonly_notice->appendChild(
                $session->make_element( "strong" )
            );

        $readonly_strong->appendChild(
            $session->make_text(
                "Web writes are disabled by configuration. "
                . "This verified preview is read-only; "
                . "no DataCite write action is available."
            )
        );

        $self->{processor}->add_message(
            "warning",
            $frag
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $warning =
        $frag->appendChild(
            $session->make_element( "p" )
        );

    my $strong =
        $warning->appendChild(
            $session->make_element( "strong" )
        );

    if( $state eq "draft" )
    {
        $strong->appendChild(
            $session->make_text(
                "Il DOI è ancora Draft. "
                . "Il pulsante seguente richiederà la pubblicazione "
                . "come Findable e registrerà il DOI in REST "
                . "solo dopo una verifica remota indipendente."
            )
        );
    }
    else
    {
        $strong->appendChild(
            $session->make_text(
                "Il DOI risulta già Findable. "
                . "Il pulsante seguente NON invierà un nuovo PUT: "
                . "effettuerà soltanto la riconciliazione locale "
                . "dopo una nuova verifica remota."
            )
        );
    }

    my $form =
        $frag->appendChild(
            $self->render_form(
                "datacite_publish_" . $eprint->id
            )
        );

    $form->appendChild(
        $session->render_action_buttons(
            datacite_publish_findable =>
                $self->phrase(
                    "publish_findable_button"
                ),
            datacite_cancel_publish =>
                $session->phrase(
                    "lib/submissionform:action_cancel"
                ),
            _order => [
                qw/
                    datacite_publish_findable
                    datacite_cancel_publish
                /
            ],
        )
    );

    $self->{processor}->add_message(
        "warning",
        $frag
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# Cancel Publish.
#
# NO DataCite operation.
############################################################

sub action_datacite_cancel_publish
{
    my( $self ) = @_;

    $self->{processor}->add_message(
        "message",
        $self->{session}->make_text(
            "DataCite Findable publication cancelled. "
            . "No DOI was published or modified."
        )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# PUBLISH DATACITE DOI AS FINDABLE.
#
# THIS IS A WRITE ACTION.
#
# The underlying Event method independently re-checks:
#   - current authenticated EPrints userid;
#   - exact PUBLISH_FINDABLE confirmation;
#   - local state;
#   - remote DOI;
#   - client ownership;
#   - landing URL;
#   - remote state.
############################################################

sub action_datacite_publish_findable
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless(
        defined $repository
        && defined $session
        && defined $eprint
    )
    {
        return undef;
    }

    unless(
           $self->_current_user_allowed()
        && $self->_web_writes_enabled()
    )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST web write denied by Screen policy."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST "
                . "could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my(
        $mode,
        $doi,
        $reason,
        $remote
    ) =
        $event->publish_mint_findable(
            $eprint,
            undef,
            undef,
            "PUBLISH_FINDABLE"
        );

    my $text =
        "DataCite REST Findable result; "
        . "mode=$mode; "
        . "eprint=" . $eprint->id . "; "
        . "doi=[" . ($doi || "") . "]; "
        . "reason=$reason";

    if( defined $remote )
    {
        $text .=
            "; state=["
            . ($remote->{state} || "")
            . "]"
            . "; url=["
            . ($remote->{url} || "")
            . "]"
            . "; client=["
            . ($remote->{_datacite_client_id} || "")
            . "]";
    }

    #
    # Reload the object after possible local commit so the
    # displayed value reflects persistent repository state.
    #
    my $fresh =
        $repository->eprint(
            $eprint->id
        );

    my $local_doi =
        defined $fresh
        ? (
            $fresh->get_value( "doi" )
            || ""
          )
        : "";

    $text .=
        "; local_doi=["
        . $local_doi
        . "]";

    my $message_type;

    if(
           $mode eq "FINDABLE_PUBLISHED"
        || $mode eq "FINDABLE_RECONCILED"
        || $mode eq "FINDABLE_ALREADY_LOCAL"
    )
    {
        $message_type = "message";
    }
    elsif(
           $mode =~ /^PUBLISH_SENT_/
        || $mode eq "PUBLISH_NOT_CONFIRMED"
        || $mode eq "FINDABLE_LOCAL_PERSIST_FAILED"
        || $mode eq "FINDABLE_LOCAL_CONFLICT"
    )
    {
        $message_type = "warning";
    }
    else
    {
        $message_type = "error";
    }

    $self->{processor}->add_message(
        $message_type,
        $session->make_text( $text )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# Permission for explicit Draft creation.
############################################################

sub allow_datacite_create_draft
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless $self->_web_writes_enabled();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Permission for cancellation.
############################################################

sub allow_datacite_cancel_draft
{
    my( $self ) = @_;

    return 0
        unless $self->_current_user_allowed();

    return 0
        unless defined
            $self->{processor}->{eprint};

    return 1;
}


############################################################
# Cancel Draft creation.
#
# NO DataCite operation.
############################################################

sub action_datacite_cancel_draft
{
    my( $self ) = @_;

    $self->{processor}->add_message(
        "message",
        $self->{session}->make_text(
            "DataCite Draft creation cancelled. "
            . "No DOI was created or modified."
        )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# CREATE DATACITE DRAFT.
#
# THIS IS A WRITE ACTION.
#
# Safety:
#   - available only to explicit write_userids;
#   - invoked from the explicit confirmation POST;
#   - underlying create_mint_draft() independently begins
#     with _write_authorised();
#   - exact CREATE_DRAFT confirmation is supplied only here;
#   - create_mint_draft() performs a fresh authenticated
#     preflight immediately before its single POST;
#   - no publish event;
#   - no local DOI persistence.
############################################################

sub action_datacite_create_draft
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless(
        defined $repository
        && defined $session
        && defined $eprint
    )
    {
        return undef;
    }

    unless(
           $self->_current_user_allowed()
        && $self->_web_writes_enabled()
    )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST web write denied by Screen policy."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        $self->{processor}->add_message(
            "error",
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST "
                . "could not be loaded."
            )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # DO NOT perform any separate preliminary write logic here.
    #
    # create_mint_draft() itself MUST retain _write_authorised()
    # as its first operation.
    #
    my(
        $mode,
        $doi,
        $reason,
        $remote
    ) =
        $event->create_mint_draft(
            $eprint,
            undef,
            undef,
            "CREATE_DRAFT"
        );

    my $text =
        "DataCite REST Draft result; "
        . "mode=$mode; "
        . "eprint=" . $eprint->id . "; "
        . "doi=[" . ($doi || "") . "]; "
        . "reason=$reason";

    if( defined $remote )
    {
        my $state =
            $remote->{state} || "";

        my $url =
            $remote->{url} || "";

        my $client =
            $remote->{_datacite_client_id}
            || "";

        $text .=
            "; state=[$state]"
            . "; url=[$url]"
            . "; client=[$client]";
    }

    my $local_doi =
        $eprint->get_value( "doi" )
        || "";

    $text .=
        "; local_doi=["
        . $local_doi
        . "]";

    my $message_type;

    if( $mode eq "DRAFT_CREATED" )
    {
        $message_type = "message";
    }
    elsif( $mode =~ /^DRAFT_CREATED_/ )
    {
        #
        # Remote object exists, but post-write verification
        # detected something requiring attention.
        #
        $message_type = "warning";
    }
    else
    {
        $message_type = "error";
    }

    $self->{processor}->add_message(
        $message_type,
        $session->make_text( $text )
    );

    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


############################################################
# READ-ONLY ACTION.
#
# It deliberately:
#   - verifies the real plugin write gate;
#   - performs the authenticated DataCite GET preflight;
#   - displays the result;
#   - performs NO DataCite POST/PUT/DELETE;
#   - performs NO EPrints record modification;
#   - creates NO event_queue object.
############################################################

sub action_datacite_preflight
{
    my( $self ) = @_;

    my $repository =
        $self->{repository};

    return undef
        unless defined $repository;

    my $session =
        $self->{session};

    my $eprint =
        $self->{processor}->{eprint};

    unless( defined $eprint )
    {
        my $msg =
            $session->make_text(
                "DataCite REST: eprint not available."
            );

        $self->{processor}->add_message(
            "error",
            $msg
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    my $event =
        $repository->plugin(
            "Event::DataCiteEventREST"
        );

    unless( defined $event )
    {
        my $msg =
            $session->make_text(
                "DataCite REST: Event::DataCiteEventREST could not be loaded."
            );

        $self->{processor}->add_message(
            "error",
            $msg
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Most important web-context test:
    # call exactly the same hard gate used by create_mint_draft().
    #
    my(
        $write_ok,
        $acting_userid,
        $write_reason
    ) =
        $event->_write_authorised();

    unless( $write_ok )
    {
        my $text =
            "DataCite REST web gate: DENY; "
            . $write_reason;

        $self->{processor}->add_message(
            "error",
            $session->make_text( $text )
        );

        $self->{processor}->{screenid} =
            "EPrint::View";

        return undef;
    }

    #
    # Authenticated Member API GET only.
    #
    my(
        $mode,
        $doi,
        $reason,
        $remote
    ) =
        $event->preflight_datacite_authenticated(
            $eprint
        );

    my $text =
        "DataCite REST preflight; "
        . "write_gate=ALLOW; "
        . "userid=$acting_userid; "
        . "mode=$mode; "
        . "doi=[" . ($doi || "") . "]; "
        . "reason=$reason";

    if( defined $remote )
    {
        my $state =
            $remote->{state}
            || "";

        my $client =
            $remote->{_datacite_client_id}
            || "";

        my $schema =
            $event->_datacite_effective_schema(
                $remote
            );

        $text .=
            "; state=[$state]"
            . "; client=[$client]"
            . "; schema=[$schema]";
    }

    my $message_type =
        $mode =~ /^BLOCK/
        ? "warning"
        : "message";

    $self->{processor}->add_message(
        $message_type,
        $session->make_text( $text )
    );

    #
    # Return to the normal eprint view.
    #
    $self->{processor}->{screenid} =
        "EPrint::View";

    return undef;
}


1;

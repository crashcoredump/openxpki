package OpenXPKI::Server::API2::Plugin::Workflow::get_rpc_openapi_spec;
use OpenXPKI::Server::API2::EasyPlugin;

=head1 NAME

OpenXPKI::Server::API2::Plugin::Workflow::get_rpc_openapi_spec

=cut

# Core modules
use List::Util;

# Project modules
use OpenXPKI::Client::Config;
use OpenXPKI::Connector::WorkflowContext;
use OpenXPKI::Server::Context qw( CTX );
use OpenXPKI::Server::API2::Types;
use OpenXPKI::Server::API2::Plugin::Workflow::Util;


our %TYPE_MAP = (
    server      => 'string',
    text        => 'string',
    uploadarea  => 'string',
);

has factory => (
    is => 'rw',
    isa => 'OpenXPKI::Workflow::Factory',
    lazy => 1,
    default => sub { CTX('workflow_factory')->get_factory },
);

=head1 COMMANDS

=head2 get_rpc_openapi_spec

Returns the OpenAPI specification for the given workflow.

Restrictions:

=over

=item *

=back




B<Parameters>

=over

=item * C<workflow> I<Str> - workflow type

=item * C<input> I<ArrayRef> - filter for input parameters (list of allowed parameters)

=item * C<output> I<ArrayRef> - filter for output parameters (list of allowed parameters)

=back

=cut
command "get_rpc_openapi_spec" => {
    workflow => { isa => 'Str', required => 1, },
    input => { isa => 'ArrayRef[Str]', required => 0, default => sub { [] } },
    output => { isa => 'ArrayRef[Str]', required => 0, default => sub { [] } },
} => sub {
    my ($self, $params) = @_;

    my $type = $params->workflow;
    my $rpc_conf = OpenXPKI::Client::Config->new('rpc');



    if (not $self->factory->authorize_workflow({ ACTION => 'create', TYPE => $type })) {
        OpenXPKI::Exception->throw(
            message => 'User is not authorized to fetch workflow info',
            params => { workflow => $type }
        );
    }

    my $head = CTX('config')->get_hash([ 'workflow', 'def', $type, 'head' ]);
    my $result = {
        type        => $type,
        label       => $head->{label},
        description => $head->{description},
    };

    my $fields = $self->_get_openapi_fields($type, $self->_get_input_fields($type, 'INITIAL'), $params->input);

    return $fields;
};

sub _get_openapi_fields {
    my ($self, $type, $fields, $wanted_field_names) = @_;

    my $wanted_fields = {};
    for my $wanted ( @$wanted_field_names ) {
        OpenXPKI::Exception->throw(
            message => 'Requested input field is not defined in any action of the workflows INITIAL state',
            params => { workflow => $type, field => $wanted }
        ) unless $fields->{$wanted};

        $wanted_fields->{$wanted} = $fields->{$wanted};
    }

    # map OpenXPKI to OpenAPI types
    for my $field (values %$wanted_fields) {
        $field->{type} = $OpenXPKI::Server::API2::Plugin::Workflow::get_rpc_openapi_spec::TYPE_MAP{$field->{type}}
            or OpenXPKI::Exception->throw(
                message => 'Field type found that has no mapping to OpenAPI type',
                params => { workflow => $type, field_type => $field->{type} }
            );
    }

    return $wanted_fields;
}

# Returns a HashRef with field names and their definition
sub _get_input_fields {
    my ($self, $type, $query_state) = @_;

    my $result = {};
    my $wf_config = $self->factory->_get_workflow_config($type);

    #
    # fetch actions in state $query_state from the config
    #
    my @actions = ();

    # get name of first action of $query_state
    my $first_action;
    for my $state (@{$wf_config->{state}}) {
        if ($state->{name} eq $query_state) {
            $first_action = $state->{action}->[0]->{name} ;
            last;
        }
    }
    OpenXPKI::Exception->throw(
        message => 'State not found in workflow',
        params => { workflow_type => $type, state => $query_state }
    ) unless $first_action;

    push @actions, $first_action;

    # get names of further actions in $query_state
    # TODO This depends on the internal naming of follow up actions in Workflow.
    #      Alternatively we could parse actions again as in OpenXPKI::Server::API2::Plugin::Workflow::Util->_get_config_details which is also not very elegant
    my $followup_state_re = sprintf '^%s_%s_\d+$', $query_state, uc($first_action);
    for my $state (@{$wf_config->{state}}) {
        if ($state->{name} =~ qr/$followup_state_re/) {
            push @actions, $state->{action}->[0]->{name} ;
        }
    }

    # get field informations
    for my $action (@actions) {
        my $action_info = $self->factory->get_action_info($action, $type);
        my $fields = $action_info->{field};
        for my $f (@$fields) {
            $result->{$f->{name}} = {
                %$f,
                action => $action
            };
        }
    }

    return $result;
}

__PACKAGE__->meta->make_immutable;

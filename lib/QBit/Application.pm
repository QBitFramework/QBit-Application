=encoding UTF-8

=head1 Name

QBit::Application - base class for create applications.

=head1 Description

It union all project models.

=cut

package QBit::Application;

use qbit;

use base qw(QBit::Class);

use QBit::Application::_Utils::TmpLocale;
use QBit::Application::_Utils::TmpRights;

=head1 RO accessors

=over

=item

B<timelog>

=back

=cut

__PACKAGE__->mk_ro_accessors(qw(timelog));

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    $self->{'__OPTIONS__'} = $self->{'__ORIG_OPTIONS__'} = {};

    my $app_module = ref($self) . '.pm';
    $app_module =~ s/::/\//g;

    $self->{'__ORIG_OPTIONS__'}{'FrameworkPath'} = $INC{'QBit/Class.pm'} =~ /(.+?)QBit\/Class\.pm$/ ? $1 : './';
    $self->{'__ORIG_OPTIONS__'}{'ApplicationPath'} =
        ($INC{$app_module} || '') =~ /(.*?\/?)(?:[^\/]*lib\/*)?$app_module$/
      ? ($1 || './')
      : './';

    package_merge_isa_data(
        ref($self),
        $self->{'__ORIG_OPTIONS__'},
        sub {
            my ($package, $res) = @_;

            my $pkg_stash = package_stash($package);

            foreach my $cfg (@{$pkg_stash->{'__OPTIONS__'} || []}) {
                $cfg->{'config'} //= $self->read_config($cfg->{'filename'});

                foreach (keys %{$cfg->{'config'}}) {
                    warn gettext('%s: option "%s" replaced', $cfg->{'filename'}, $_)
                      if exists($res->{$_});
                    $res->{$_} = $cfg->{'config'}{$_};
                }
            }
        },
        __PACKAGE__
    );

    my $locales = $self->get_option('locales', {});
    if (%$locales) {
        my ($locale) = grep {$locales->{$_}{'default'}} keys(%$locales);
        ($locale) = keys(%$locales) unless $locale;

        $self->set_app_locale($locale);
    }

    if ($self->get_option('preload_accessors')) {
        $self->$_ foreach keys(%{$self->get_models()});
    }

    delete($self->{'__OPTIONS__'});    # Options initializing in pre_run
}

=head1 Package methods

=head2 config_opts

Set options in config

B<Arguments:>

=over

=item

B<%opts> - Options (type: hash)

=back

B<Example:>

  __PACKAGE__->config_opts(param_name => 'Param');
  
  # late in your code
  
  my $param = $self->get_option('param_name'); # 'Param'

=cut

sub config_opts {
    my ($self, %opts) = @_;

    my $class = ref($self) || $self;

    my $pkg_name = $class;
    $pkg_name =~ s/::/\//g;
    $pkg_name .= '.pm';

    $self->_push_pkg_opts($INC{$pkg_name} || $pkg_name => \%opts);
}

=head2 use_config

Set a file in config queue. The configuration is read in sub "init". In the same place are set the settings B<ApplicationPath> and B<FrameworkPath>.

B<QBit::Application options:>

=over

=item

B<preload_accessors> - type: int, values: 1/0 (1 - preload accessors, 0 - lazy load, default: 0)

=item

B<timelog_class> - type: string, values: B<QBit::TimeLog::XS/QBit::TimeLog> (default: B<QBit::TimeLog> - this is not a production solution, in production use XS version)

=item

B<locale_domain> - type: string, value: <your domain> (used in set_locale for B<Locale::Messages::textdomain>, default: 'application')

=item

B<find_app_mem_cycle> - type: int, values: 1/0 (1 - find memory cycle in post_run, used Devel::Cycle, default: 0)

=back

B<QBit::WebInterface options:>

=over

=item

B<salt> - type: string, value: <your salt> (used for generate csrf token)

=item

B<TemplateCachePath> - type: string, value: <your path for template cache> (default: "/tmp")

=item

B<show_timelog> - type: int, values: 1/0 (1 - view timelog in html footer, default: 0)

=item

B<TemplateIncludePaths> - type: array of a string: value: [<your path for templates>]

  already used:
  - <project_path>/templates         # project_path   = $self->get_option('ApplicationPath')
  - <framework_path>/QBit/templates  # framework_path = $self->get_option('FrameworkPath')

=back

B<QBit::WebInterface::Routing options:>

=over

=item

B<controller_class> - type: string, value: <your controller class> (default: B<QBit::WebInterface::Controller>)

=item

B<use_base_routing> - type: int, values: 1/0 (1 - also use routing from B<QBit::WebInterface::Controller>, 0 - only use routing from B<QBit::WebInterface::Routing>)

=back

B<Arguments:>

=over

=item

B<$filename> - Config name (type: string)

=back

B<Example:>

  __PACKAGE__->use_config('Application.cfg');  # or __PACKAGE__->use_config('Application.json');

  # later in your code:

  my preload_accessors = $app->get_optin('preload_accessors');

=cut

sub use_config {
    my ($self, $filename) = @_;

    $self->_push_pkg_opts($filename);
}

=head2 read_config

read config by path or name from folder "configs".

  > tree ./Project

  Project
  ├── configs
  │   └── Application.cfg
  └── lib
      └── Application.pm

B<Formats:>

=over

=item

B<cfg> - perl code

  > cat ./configs/Application.cfg

  preload_accessors => 1,
  timelog_class => 'QBit::TimeLog::XS',
  locale_domain => 'domain.local',
  TemplateIncludePaths => ['${ApplicationPath}lib/QBit/templates'],

=item

B<json> - json format

  > cat ./configs/Application.json

  {
    "preload_accessors" : 1,
    "timelog_class" : "QBit::TimeLog::XS",
    "locale_domain" : "domain.local",
    "TemplateIncludePaths" : ["${ApplicationPath}lib/QBit/templates"]
  }

=back

B<Arguments:>

=over

=item

B<$filename> - Config name (type: string)

=back

B<Return value:>  Options (type: ref of a hash)

B<Example:>

  my $config = $self->read_config('Application.cfg');

=cut

sub read_config {
    my ($self, $filename) = @_;

    unless (-f $filename) {
        foreach (qw(lib configs)) {
            my $possible_file = $self->get_option('ApplicationPath') . "$_/$filename";

            if (-f $possible_file) {
                $filename = $possible_file;

                #TODO: use only configs
                if ($_ eq 'lib') {
                    warn gettext('For configs, use the "configs" folder in the project root.');
                }

                last;
            }
        }
    }

    my $config = {};

    try {
        if ($filename =~ /\.cfg\z/) {
            $config = {do $filename};
        } elsif ($filename =~ /\.json\z/) {
            $config = from_json(readfile($filename));
        } else {
            throw gettext('Unknown config format: %s', $filename);
        }
    }
    catch {
        my ($exception) = @_;

        throw gettext('Read config file "%s" failed: %s', $filename, $exception->message);
    };

    throw gettext('Config "%s" must be a hash') if ref($config) ne 'HASH';

    return $config;
}

=head2 get_option

Get option value by name.

B<Arguments:>

=over

=item

B<$name> - Option name (type: string)

=item

B<$default> - Default value

=back

B<Return value:> Option value

B<Example:>

  my $param = $self->get_option('paramName', 0);

=cut

sub get_option {
    my ($self, $name, $default) = @_;

    my $res = $self->{'__OPTIONS__'}{$name} || return $default;

    foreach my $str (ref($res) eq 'ARRAY' ? @$res : $res) {
        while ($str =~ /^(.*?)(?:\$\{([\w\d_]+)\})(.*)$/) {
            $str = ($1 || '') . ($self->get_option($2) || '') . ($3 || '');
        }
    }

    return $res;
}

=head2 set_option

Set option by name.

B<Arguments:>

=over

=item

B<$name> - Option name (type: string)

=item

B<$value> - Option value

=back

B<Return value:> Option value

B<Example:>

  $self->set_option('paramName' => 1);

=cut

sub set_option {
    my ($self, $name, $value) = @_;

    $self->{'__OPTIONS__'}{$name} = $value;
}

=head2 get_models

Returns all models.

B<No arguments.>

B<Return value:> $models - ref of a hash

B<Examples:>

  my $models = $self->get_models();

  # $models = {
  #     users => 'Application::Model::Users',
  #     ...
  # }

=cut

sub get_models {
    my ($self) = @_;

    my $models = {};

    package_merge_isa_data(
        ref($self),
        $models,
        sub {
            my ($package, $res) = @_;

            my $pkg_models = package_stash($package)->{'__MODELS__'} || {};
            $models->{$_} = $pkg_models->{$_} foreach keys(%$pkg_models);
        },
        __PACKAGE__
    );

    return $models;
}

=head2 get_registered_rights

Returns all registered rights

B<No arguments.>

B<Return value:> ref of a hash

B<Example:>

  my $registered_rights = $self->get_registered_rights();
  
  # $registered_rights = {
  #     view_all => {
  #         name  => 'Right to view all elements',
  #         group => 'elemets'
  #     },
  #     ...
  # }

=cut

sub get_registered_rights {
    my ($self) = @_;

    my $rights = {};
    package_merge_isa_data(
        ref($self),
        $rights,
        sub {
            my ($ipackage, $res) = @_;

            my $ipkg_stash = package_stash($ipackage);
            $res->{'__RIGHTS__'} = {%{$res->{'__RIGHTS__'} || {}}, %{$ipkg_stash->{'__RIGHTS__'} || {}}};
        },
        __PACKAGE__
    );

    return $rights->{'__RIGHTS__'};
}

sub get_registred_rights {&get_registered_rights;}

=head2 get_registered_right_groups

Returns all registered right groups.

B<No arguments.>

B<Return value:> $registered_right_groups - ref of a hash

B<Example:>

  my $registered_right_groups = $self->get_registered_right_groups();

  # $registered_right_groups = {
  #     elements => 'Elements',
  # }

=cut

sub get_registered_right_groups {
    my ($self) = @_;

    my $rights = {};
    package_merge_isa_data(
        ref($self),
        $rights,
        sub {
            my ($ipackage, $res) = @_;

            my $ipkg_stash = package_stash($ipackage);
            $res->{'__RIGHT_GROUPS__'} =
              {%{$res->{'__RIGHT_GROUPS__'} || {}}, %{$ipkg_stash->{'__RIGHT_GROUPS__'} || {}}};
        },
        __PACKAGE__
    );

    return $rights->{'__RIGHT_GROUPS__'};
}

sub get_registred_right_groups {&get_registered_right_groups;}

=head2 check_rights

Short method description

B<Arguments:>

=over

=item

B<@rights> - type, description

=back

B<Return value:> type, description

=cut

sub check_rights {
    my ($self, @rights) = @_;

    return FALSE unless @rights;

    my $cur_user = $self->get_option('cur_user');
    my $cur_rights;

    if ($cur_user) {
        $cur_rights = $cur_user->{'rights'};

        unless (defined($cur_rights)) {
            my $cur_roles = $self->rbac->get_cur_user_roles();

            $cur_rights =
              {map {$_->{'right'} => TRUE}
                  @{$self->rbac->get_roles_rights(fields => [qw(right)], role_id => [keys(%$cur_roles)])}};

            $cur_user->{'rights'} = $cur_rights if defined($cur_user);
        }
    }

    my %user_and_temp_rights;
    push_hs(%user_and_temp_rights, $cur_rights) if $cur_rights;
    push_hs(%user_and_temp_rights, \%{$self->{'__TMP_RIGHTS__'} || {}});

    foreach (@rights) {
        return FALSE unless ref($_) ? scalar(grep($user_and_temp_rights{$_}, @$_)) : $user_and_temp_rights{$_};
    }

    return TRUE;
}

=head2 set_app_locale

Short method description

B<Arguments:>

=over

=item

B<$locale_id> - type, description

=back

B<Return value:> type, description

=cut

sub set_app_locale {
    my ($self, $locale_id) = @_;

    my $locale = $self->get_option('locales', {})->{$locale_id};
    throw gettext('Unknown locale') unless defined($locale);
    throw gettext('Undefined locale code for locale "%s"', $locale_id) unless $locale->{'code'};

    set_locale(
        project => $self->get_option('locale_domain', 'application'),
        path    => $self->get_option('ApplicationPath') . '/locale',
        lang    => $locale->{'code'},
    );

    $self->set_option(locale => $locale_id);
}

=head2 set_tmp_app_locale

Short method description

B<Arguments:>

=over

=item

B<$locale_id> - type, description

=back

B<Return value:> type, description

=cut

sub set_tmp_app_locale {
    my ($self, $locale_id) = @_;

    my $old_locale_id = $self->get_option('locale');
    $self->set_app_locale($locale_id);

    return QBit::Application::_Utils::TmpLocale->new(app => $self, old_locale => $old_locale_id);
}

=head2 add_tmp_rights

Short method description

B<Arguments:>

=over

=item

B<@rights> - type, description

=back

B<Return value:> type, description

=cut

sub add_tmp_rights {
    my ($self, @rights) = @_;

    return QBit::Application::_Utils::TmpRights->new(app => $self, rights => \@rights);
}

=head2 pre_run

Short method description

B<No arguments.>

B<Return value:> type, description

=cut

sub pre_run {
    my ($self) = @_;

    $self->{'__OPTIONS__'} = clone($self->{'__ORIG_OPTIONS__'});

    unless (exists($self->{'__TIMELOG_CLASS__'})) {
        my $tl_package = $self->{'__TIMELOG_CLASS__'} = $self->get_option('timelog_class', 'QBit::TimeLog');

        $tl_package =~ s/::/\//g;
        $tl_package .= '.pm';
        require $tl_package;
    }

    $self->{'timelog'} = $self->{'__TIMELOG_CLASS__'}->new();
    $self->{'timelog'}->start(gettext('Total application run time'));

    foreach (keys(%{$self->get_models()})) {
        $self->$_->pre_run() if exists($self->{$_}) && $self->{$_}->can('pre_run');
    }
}

=head2 post_run

Short method description

B<No arguments.>

B<Return value:> type, description

=cut

sub post_run {
    my ($self) = @_;

    foreach (keys(%{$self->get_models()})) {
        $self->$_->finish()   if exists($self->{$_}) && $self->{$_}->can('finish');
        $self->$_->post_run() if exists($self->{$_}) && $self->{$_}->can('post_run');
    }

    $self->timelog->finish();

    $self->process_timelog($self->timelog);

    if ($self->get_option('find_app_mem_cycle')) {
        if (eval {require 'Devel/Cycle.pm'}) {
            Devel::Cycle->import();
            my @cycles;
            Devel::Cycle::find_cycle($self, sub {push(@cycles, shift)});
            $self->process_mem_cycles(\@cycles) if @cycles;
        } else {
            l(gettext('Devel::Cycle is not installed'));
        }
    }
}

=head2 process_mem_cycles

Short method description

B<Arguments:>

=over

=item

B<$cycles> - type, description

=back

B<Return value:> type, description

=cut

sub process_mem_cycles {
    my ($self, $cycles) = @_;

    my $counter = 0;
    my $text    = '';
    foreach my $path (@$cycles) {
        $text .= gettext('Cycle (%s):', ++$counter) . "\n";
        foreach (@$path) {
            my ($type, $index, $ref, $value, $is_weak) = @$_;
            $text .= gettext(
                "\t%30s => %-30s\n",
                ($is_weak ? 'w-> ' : '') . Devel::Cycle::_format_reference($type, $index, $ref, 0),
                Devel::Cycle::_format_reference(undef, undef, $value, 1)
            );
        }
        $text .= "\n";
    }

    l($text);
    return $text;
}

=head2 process_timelog

Short method description

B<No arguments.>

B<Return value:> type, description

=cut

sub process_timelog { }

=head2 _push_pkg_opts

Short method description

B<Arguments:>

=over

=item

B<$filename> - type, description

=item

B<$config> - type, description

=back

B<Return value:> type, description

=cut

sub _push_pkg_opts {
    my ($self, $filename, $config) = @_;

    my $pkg_stash = package_stash(ref($self) || $self);

    $pkg_stash->{'__OPTIONS__'} = []
      unless exists($pkg_stash->{'__OPTIONS__'});

    push(
        @{$pkg_stash->{'__OPTIONS__'}},
        {
            filename => $filename,
            config   => $config,
        }
    );
}

TRUE;

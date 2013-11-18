package vmAPI;

use strict;

use VMware::VIRuntime;
#use VMware::Vix::Simple;
#use VMware::Vix::API::Constants;

sub new
{
	my $caller = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	my $class = ref($caller) || $caller;
	
	my $self = {
		'_vix_vm_handle' => {},
	};
	
	Opts::parse();
	Opts::validate();
	
	bless $self, $class;
	
	return $self;
}

sub connect
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $vim = $self->{'_vim_obj'} = Vim->new();
	my $vim_session_id = $self->{'_vim_session_id'} || $args->{'session_id'};
	
	if(!$vim_session_id || $vim->get_session_id_status('session_id' => $vim_session_id) ne $Vim::SESSION_STATUS_OK)
	{
		$vim->login(
			'username' => Opts::get_option('username'),
			'password' => Opts::get_option('password'),
		);
	}
	else
	{
		$vim->load_session('session_id' => $vim_session_id);
	}
	
	return $vim;
}

sub disconnect
{
	my $self = shift;
	
	my $vim_session = $self->vim_session('no_connect' => 1);
	
	$vim_session->disconnect() if $vim_session;
}

sub logout
{
	my $self = shift;
	
	my $vim_session = $self->vim_session('no_connect' => 1);
	
	$vim_session->logout() if $vim_session;
}

sub vim_session
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	if(!$self->{'_vim_obj'} && !$args->{'no_connect'})
	{
		$self->connect();
	}
	
	return $self->{'_vim_obj'};
}

sub vim_service
{
	my $self = shift;
	
	return $self->vim_session()->get_vim_service();
}

sub vim_service_content
{
	my $self = shift;
	
	return $self->vim_session()->get_service_content();
}

sub na_server
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	if(!$args->{'server'})
	{
		return {'vmapi_error_code' => '500', 'vmapi_error' => 'SAN server not specified'};
	}
	
	if(!$self->{'_NaServer'} || !$self->{'_NaServer'}->{$args->{'server'}})
	{
		require NaServer;
		
		$self->{'_NaServer'} = {} if !$self->{'_NaServer'};
		
		my $s = $self->{'_NaServer'}->{$args->{'server'}} = NaServer->new(
			$args->{'server'},
			1,
			1
		);
		$s->set_admin_user('root', 'pa66w9rd-');
		$s->set_transport_type('HTTPS');
	}
	
	return $self->{'_NaServer'}->{$args->{'server'}};
}

sub na_element_to_hash
{
	my $e = shift;
	
	if($e->has_children())
	{
		my $hash = {};
	
		foreach my $child ($e->children_get())
		{
			$hash->{$child->{'name'}} = na_element_to_hash($child);
		}
		
		return $hash;
	}
	
	return $e->{'content'};
}

sub list
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $view_type = $args->{'view_type'};
	
	eval { VIMRuntime::load($view_type); };
	
	if($@ || !$view_type->isa('EntityViewBase'))
	{
		return {'vmapi_error_code' => '404', 'vmapi_error' => "$view_type is not a ManagedEntity"};
	}
	
	my $views = $self->vim_session()->find_entity_views(
		'view_type' => $view_type,
		'filter' => $args->{'filter'},
		'properties' => $args->{'properties'},
	);
	
	return $views;
}

sub viobj_to_hash
{
	my $obj = shift;
	
	return if ref($obj) eq 'HASH';
	
	my $properties = undef;
	
	if(ref($obj) eq 'ARRAY')
	{
		$properties = [];
		
		foreach my $o (@$obj)
		{
			push @$properties, viobj_to_hash($o);
		}
	}
	elsif(ref($obj))
	{
		if($obj->isa('SimpleType'))
		{
			return $obj->val();
		}
		
		$properties = {};
		
		return $properties if !$obj;
		
		$properties->{'__TYPE__'} = ref($obj);
		
		foreach my $prop (sort { $a->[0] cmp $b-> [0]; } $obj->get_property_list())
		{
			$properties->{$prop->[0]} = undef;
			
			if($obj->{$prop->[0]})
			{
				if($prop->[2])
				{
					$properties->{$prop->[0]} = [];
					
					foreach my $p (@{$obj->{$prop->[0]}})
					{
						if($prop->[1])
						{
							push @{$properties->{$prop->[0]}}, viobj_to_hash($p);
						}
						else
						{
							push @{$properties->{$prop->[0]}}, $p;
						}
					}
				}
				elsif(ref($obj->{$prop->[0]}) || $prop->[1])
				{
					if(ref($obj->{$prop->[0]}))
					{
						$properties->{$prop->[0]} = viobj_to_hash($obj->{$prop->[0]})
					}
					else
					{
						$properties->{$prop->[0]} = $obj->{$prop->[0]};
					}
				}
				else
				{
					$properties->{$prop->[0]} = $obj->{$prop->[0]};
				}
			}
			else
			{
				$properties->{$prop->[0]} = ($prop->[2]) ? [] : undef;
			}
		}
	}
	else
	{
		return $obj;
	}
	
	return $properties;
}

sub find_entity_view
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $views = $self->vim_session()->find_entity_views(
		'view_type' => $args->{'view_type'},
		'filter' => $args->{'filter'},
		'properties' => $args->{'properties'},
	);
	
	return shift @$views
		if(scalar(@$views) == 1);
	
	return { 'vmapi_error_code' => '404', 'vmapi_error' => sprintf('%s not found.', $args->{'view_type'}) };
}

sub mor_to_views
{
	my $self = shift;
	my $mo_refs = ref($_[0]) eq 'ARRAY' ? shift : [ @_ ];
	
	return $self->vim_session()->get_views('mo_ref_array' => $mo_refs);
}

sub find_view
{
	my $views = ref($_[0]) eq 'ARRAY' ? shift : [ @_ ];
	my $match = shift;
	my $filter = shift;
	
	my $view = undef;
	
	if($match && $filter)
	{
		foreach my $v (@$views)
		{
			$view = $v, last
				if(&$filter($v, $match));
		}
	}
	else
	{
		$view = shift @$views;
	}
	
	return $view;
}

sub find_vmdk {
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
 	my $vmdk_info = [];
	
	if(!$args->{'datastore'})
	{
		my $datacenters = $self->mor_to_views(
			$self->mor_to_views($self->vim_service_content()->rootFolder())->[0]->childEntity()
		);
		
		foreach my $dc (@$datacenters)
		{
			my $ds_folder = $self->mor_to_views($dc->datastore());
			
			foreach my $datastore (@$ds_folder)
			{
				push @$vmdk_info, @{ $self->find_vmdk(
					%$args,
					'datastore' => $datastore,
				)};
				
				return $vmdk_info if($args->{'vmdk_file'} && scalar(@$vmdk_info));
			}
		}
		
		return $vmdk_info;
	}
	
	my $datastore = $args->{'datastore'};
	
	my $browser = shift @{$self->mor_to_views($datastore->browser())};
	my $ds_path = $args->{'search_ds_path'} || '[' . $datastore->info()->name() . ']';
	
	my $disk_query = VmDiskFileQuery->new(
		'details' => VmDiskFileQueryFlags->new(
			'capacityKb' => 1,
			'diskType' => 1,
			'hardwareVersion' => 1,
			'thin' => 1,
		)
	);
	
	my $search_spec = HostDatastoreBrowserSearchSpec->new(
		'query' => [ $disk_query ],
		'details' => FileQueryFlags->new(
			'fileOwner' => 0,
			'fileSize' => 1,
			'fileType' => 1,
			'modification' => 0
		)
	);
	
	if($args->{'match_pattern'})
	{
		$search_spec->{'matchPattern'} = ref($args->{'match_pattern'}) eq 'ARRAY' ? $args->{'match_pattern'} : [ $args->{'match_pattern'} ];
	}
	
	my $results = $browser->SearchDatastoreSubFolders(
		'datastorePath' => $ds_path,
		'searchSpec' => $search_spec
	);
	
	if($results)
	{
		foreach my $result (@$results)
		{
			next if(!$result->file);
			
			foreach my $file (@{$result->file})
			{
				next if(ref($file) ne 'VmDiskFileInfo');
				
				my $info = {
					'VmDiskFileInfo' => $file,
					'folderPath' => $result->folderPath,
					'datastore' => $datastore
				};
				
				if($args->{'vmdk_file'} && $file->path() eq $args->{'vmdk_file'})
				{
					return [ $info ];
				}
				elsif(!$args->{'vmdk_file'})
				{
					push @$vmdk_info, $info;
				}
			}
		}
	}
	
	return $vmdk_info;
}

sub create_vm
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $missing_args = [ grep { $_ if !defined $args->{$_} } qw(vmname guest_id memory disk_size) ];
	
	if(scalar @$missing_args)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => sprintf('Missing arguments %s.', join(', ', @$missing_args)) };
	}
	
	my $vim = $self->vim_session();
	
	my $datacenter_view = $self->find_entity_view(
		'view_type' => 'Datacenter',
		'filter' => ($args->{'datacenter'}) ? { 'name' => $args->{'datacenter'} } : undef
	);
	
	if($datacenter_view->{'vmapi_error_code'})
	{
		return $datacenter_view;
	}
	
	my $computer_resource_view = undef;
	
	if($args->{'computer_resource'})
	{
		$computer_resource_view = $self->find_entity_view(
			'view_type' => 'ClusterComputeResource',
			'filter' => { 'name' => $args->{'computer_resource'} }
		);
	}
	else
	{
		$computer_resource_view = $self->mor_to_views(
			$self->mor_to_views($datacenter_view->hostFolder())->[0]->childEntity()
		)->[0];
	}
	
	if(!$computer_resource_view)
	{
		return { 'vmapi_error_code' => '404', 'vmapi_error' => 'ComputerResource not found.' };
	}
	
	my $host_view = find_view(
		$self->mor_to_views($computer_resource_view->host),
		$args->{'vmhost'},
		sub { $_[0]->name() eq $_[1] }
	);
	
	if(!$host_view)
	{
		return { 'vmapi_error_code' => '404', 'vmapi_error' => sprintf('HostSystem %s not found.', $args->{'vmhost'}) };
	}
	
	my $datastore_view = find_view(
		$self->mor_to_views($host_view->datastore()),
		$args->{'datastore'},
		sub { $_[0]->summary()->name() eq $_[1] }
	);
	
	if(!$datastore_view)
	{
		return { 'vmapi_error_code' => '404', 'vmapi_error' => sprintf('Datastore %s not found.', $args->{'datastore'}) };
	}
	
	my $datastore_path = sprintf('[%s]', $datastore_view->summary()->name());
	
	my $network_view = find_view(
		$self->mor_to_views($host_view->network()),
		$args->{'network'},
		sub { $_[0]->summary()->name() eq $_[1] }
	);
	
	if(!$network_view)
	{
		return { 'vmapi_error_code' => '404', 'vmapi_error' => sprintf('Network %s not found.', $args->{'network'}) };
	}
	
	my $vm_devices = [];
	
	push @$vm_devices, _create_pv_scsi_controller(
#		'pv' => !$args->{'legacy'},
		'pv' => 1,
	);
	
	push @$vm_devices, _create_virtual_disk(
		'datastore_path' => $datastore_path,
		'disk_size' => $args->{'disk_size'},
		'unit_number' => scalar(@$vm_devices) - 1,
	);
	
	push @$vm_devices, _create_pv_nic(
		'network' => $network_view,
		'unit_number' => scalar(@$vm_devices) - 1,
#		'vmxnet' => !$args->{'legacy'},
		'vmxnet' => 1,
	);
	
	my $vm_config_spec = VirtualMachineConfigSpec->new(
		'cpuHotAddEnabled' => 'true',
		'cpuHotRemoveEnabled' => 'true',
		'guestId' => $args->{'guest_id'},
		'memoryHotAddEnabled' => 'true',
		'memoryMB' => $args->{'memory'},
		'name' => $args->{'vmname'},
		'numCPUs' => $args->{'num_cpus'} || 1,
		
		'deviceChange' => $vm_devices,
		'files' => VirtualMachineFileInfo->new(
			'logDirectory' => undef,
			'snapshotDirectory' => undef,
			'suspendDirectory' => undef,
			'vmPathName' => $datastore_path,
		),
	);
	
	my $folder = $vim->get_view('mo_ref' => $datacenter_view->vmFolder());
	my $virtual_machine = undef;
	
	eval
	{
		$folder->CreateVM(
			'config' => $vm_config_spec,
			'pool' => $vim->get_view('mo_ref' => $host_view->parent())->resourcePool
		);
		
		$virtual_machine = $vim->find_entity_view(
			'view_type' => 'VirtualMachine',
			'filter' => { 'name' => $args->{'vmname'} },
		);
	};
	
	return $virtual_machine || { 'vmapi_error_code' => '500', 'vmapi_error' => $@->{'fault_string'} || ${$@->detail}{'text'} };
}

sub destroy_vm
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $view = $self->find_entity_view(
		'view_type' => 'VirtualMachine',
		'filter' => { 'config.uuid' => $args->{'uuid'} },
	);
	
	if($view->{'vmapi_error_code'})
	{
		return $view;
	}
	elsif($view->runtime()->powerState()->val() eq 'poweredOn')
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'VM can not be destroyed [Powered On]' };
	}
	
	$view->Destroy();
	
	return $view;
}

sub _create_pv_nic
{
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $backing = VirtualEthernetCardNetworkBackingInfo->new(
		'deviceName' => $args->{'network'}->summary()->name(),
		'network' => $args->{'network'}
	);
	
	my $device = undef;
	
	if($args->{'vmxnet'})
	{
		$device = VirtualVmxnet3->new(
			'backing' => $backing,
			'key' => '0',
			'unitNumber' => $args->{'unit_number'},
			'addressType' => 'generated',
			'connectable' => VirtualDeviceConnectInfo->new(
				'allowGuestControl' => 'true',
				'connected' => 'false',
				'startConnected' => 'true'
			)
		);
	}
	else
	{	
		$device = VirtualE1000->new(
			'backing' => $backing,
			'key' => '0',
			'unitNumber' => $args->{'unit_number'},
			'addressType' => 'generated',
			'connectable' => VirtualDeviceConnectInfo->new(
				'allowGuestControl' => 'true',
				'connected' => 'false',
				'startConnected' => 'true'
			)
		);
	}
	
	return VirtualDeviceConfigSpec->new(
		'device' => $device,
		'operation' => VirtualDeviceConfigSpecOperation->new('add'),
	);
}

sub _create_pv_scsi_controller
{
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $device = undef;
	
	if($args->{'pv'})
	{
		$device = ParaVirtualSCSIController->new(
			'key' => '0',
			'device' => [ 0 ],
			'busNumber' => '0',
			'sharedBus' => VirtualSCSISharing->new('noSharing'),
		);
	}
	else
	{	
		$device = VirtualLsiLogicController->new(
			'key' => '0',
			'device' => [ 0 ],
			'busNumber' => '0',
			'sharedBus' => VirtualSCSISharing->new('noSharing'),
		);
	}
	
	return VirtualDeviceConfigSpec->new(
		'device' => $device,
		'operation' => VirtualDeviceConfigSpecOperation->new('add')
	);
}

sub _create_virtual_disk
{
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	return VirtualDeviceConfigSpec->new(
		'device' => VirtualDisk->new(
			'backing' => VirtualDiskFlatVer2BackingInfo->new(
				'diskMode' => 'persistent',
				'fileName' => $args->{'datastore_path'},
				'thinProvisioned' => 'true'
			),
			'controllerKey' => '0',
			'key' => '0',
			'unitNumber' => $args->{'unit_number'},
			'capacityInKB' => $args->{'disk_size'}
		),
		'fileOperation' => VirtualDeviceConfigSpecFileOperation->new('create'),
		'operation' => VirtualDeviceConfigSpecOperation->new('add'),
	);
}

sub create_vdk
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $vdm = shift @{$self->mor_to_views($self->vim_service_content()->{'virtualDiskManager'})};
	my $datacenter = $self->find_entity_view(
		'view_type' => 'Datacenter',
		'filter' => { 'name' => $args->{'datacenter'} }
	);
	
	my $vdk = undef;
	
	eval
	{
		$vdk = $vdm->CreateVirtualDisk(
			'name' => $args->{'name'},
			'datacenter' => $datacenter,
			'spec' => FileBackedVirtualDiskSpec->new(
				'adapterType' => $args->{'adapterType'},
				'capacityKb' => $args->{'capacityKb'},
				'diskType' => $args->{'diskType'},
			)
		);
	};
	
	return $vdk || { 'vmapi_error_code' => '500', 'vmapi_error' => $@->{'fault_string'} || ${$@->detail}{'text'} };
}

sub clone_vmdk
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $src_ds_path = undef;
	my $dest_ds_path = undef;
	
	# Read in source VDMK descriptor file
	my $na_server = $self->na_server(
		'server' => 'usiadsan101.lsi.prod'
	);
	
	my $na_file_path = sprintf(
		'/vol/%s/%s',
		($args->{'src_ds_path'} =~ /^\[(.+)\] (.+)$/)
	);
	
	my $na_result = $na_server->invoke(
		'file-get-file-info',
		'path',
		$na_file_path
	);
	
	if($na_result->results_status() ne 'passed')
	{
		return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
	}
	
	my $na_file_info = $na_result->child_get('file-info');
	
	$na_result = $na_server->invoke(
		'file-read-file',
		'path',
		$na_file_path,
		'length',
		$na_file_info->child_get_int('file-size'),
		'offset',
		0
	);
	
	if($na_result->results_status() ne 'passed')
	{
		return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
	}
	
	my $vmdk_file_data = pack('H*', $na_result->child_get_string('data'));
	
	# remove uuid
	$vmdk_file_data =~ s/^ddb.uuid.*$//mg;
	
	$na_file_path = sprintf(
		'/vol/%s/%s',
		($args->{'dest_ds_path'} =~ /^\[(.+)\] (.+)$/)
	);
	
	my $na_path = join('/', splice(@{[split('/', $na_file_path)]}, 0, 3));
	
	foreach my $dir (splice(@{[ split('/', $na_file_path) ]}, 3, -1))
	{
		my $na_result = $na_server->invoke(
			'file-get-file-info',
			'path',
			$na_path .= '/' . $dir
		);
		
		if($na_result->results_status() ne 'passed')
		{
			my $na_result = $na_server->invoke(
				'file-create-directory',
				'path',
				$na_path,
				'perm',
				'0755'
			);
			
			if($na_result->results_status() ne 'passed')
			{
				return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
			}
		}
		else
		{
			my $na_file_info = $na_result->child_get('file-info');
			
			if($na_file_info->child_get_string('file-type') ne 'directory')
			{
				return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_path . ' is not a directory' };
			}
		}
	}
	
	$na_result = $na_server->invoke(
		'file-write-file',
		'path',
		$na_file_path,
		'offset',
		0,
		'overwrite',
		$args->{'overwrite'} || 0,
		'data',
		unpack('H*', $vmdk_file_data)
	);
	
	if($na_result->results_status() ne 'passed')
	{
		return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
	}
	
	my $source_file = sprintf(
		'/vol/%s/%s',
		($args->{'src_ds_path'} =~ /^\[(.+)\] (.+)$/)
	);
	$source_file =~ s/\.vmdk/-flat.vmdk/;
	
	my $clone_file = sprintf(
		'/vol/%s/%s',
		($args->{'dest_ds_path'} =~ /^\[(.+)\] (.+)$/)
	);
	$clone_file =~ s/\.vmdk/-flat.vmdk/;
	
	$na_result = $na_server->invoke(
		'clone-start',
		'source-path',
		$source_file,
		'destination-path',
		$clone_file,
	);
	
	if($na_result->results_status() ne 'passed')
	{
		return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
	}
	
	my $clone_id = na_element_to_hash(
		$na_result->child_get('clone-id')
	);
	
	return {
		'san_server' => $na_server->{'server'},
		'clone-id' => $clone_id,
	}
}

sub clone_vmdk_status
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $na_server = $self->na_server(
		'server' => $args->{'san_server'}
	);
	
	my $in = NaElement->new('clone-list-status');
	
	if($args->{'clone-id'})
	{
		my $clone_id_info = NaElement->new('clone-id-info');
		$clone_id_info->child_add_string(
			'volume-uuid',
			$args->{'clone-id'}->{'clone-id-info'}->{'volume-uuid'}
		);
		$clone_id_info->child_add_string(
			'clone-op-id',
			$args->{'clone-id'}->{'clone-id-info'}->{'clone-op-id'}
		);
		
		my $clone_id = NaElement->new('clone-id');
		$clone_id->child_add($clone_id_info);
		
		$in->child_add($clone_id);
	}
	
	my $na_result = $na_server->invoke_elem($in);
	
	if($na_result->results_status() ne 'passed')
	{
		return { 'vmapi_error_code' => 500, 'vmapi_error' => $na_result->results_reason() };
	}
	
	return {
		%{ na_element_to_hash(
			$na_result->child_get('status')->child_get('ops-info')
		) },
		'san_server' => $args->{'san_server'}
	};
}

sub _attach_vmdk_spec
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $v = $self->find_entity_view(
		'view_type' => 'VirtualMachine',
		'filter' => { 'config.name' => $args->{'vm_name'} },
	);
	
	if(!$v)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'VM not found' };
	}
	
	my $vmdk_info = undef;
	
	if($args->{'vmdk_name'} && !$args->{'vmdk_ds_path'})
	{
		$vmdk_info = shift @{$self->find_vmdk(
			'vmdk_file' => $args->{'vmdk_name'}
		)};
	}
	elsif($args->{'vmdk_ds_path'})
	{
		my ($ds_name) = ($args->{'vmdk_ds_path'} =~ /\[([^\]]+)\]/);
		
		my $datastore = $self->find_entity_view(
			'view_type' => 'Datastore',
			'filter' => { 'name' => $ds_name }
		);
		
		my ($search_ds_path, $vmdk_file) = ($args->{'vmdk_ds_path'} =~ /(?:(.+)\/)?(.+\.vmdk)/);
		
		$vmdk_info = shift @{$self->find_vmdk(
			'datastore' => $datastore,
			'search_ds_path' => $search_ds_path,
			'vmdk_file' => $vmdk_file
		)};
	}
	
	if(!$vmdk_info)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'VMDK not found' };
	}
	
	my $disk = shift @{[ grep {
		ref($_) eq 'VirtualDisk' && $_->backing()->fileName() eq $vmdk_info->{'folderPath'} . $vmdk_info->{'VmDiskFileInfo'}->path()
	} @{$v->config()->hardware()->device()} ]};
	
	if($disk)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'Disk already attached' };
	}
	
	my $scsi_device = shift @{[ grep { ref($_) =~ /(?:SCSI|Logic)Controller$/; } @{$v->config()->hardware()->device()} ]};
	
	my $unit_number = (($scsi_device->{'device'}) ? scalar(@{$scsi_device->device()}) : 0);
	
	my $disk = VirtualDisk->new(
		'controllerKey' => $scsi_device->key(),
		'unitNumber' => $unit_number,
		'key' => '-1',
		'backing' => VirtualDiskFlatVer2BackingInfo->new(
			'datastore' => $vmdk_info->{'datastore'},
			'fileName' => $vmdk_info->{'folderPath'} . $vmdk_info->{'VmDiskFileInfo'}->path(),
			'diskMode' => 'persistent'
       ),
		'capacityInKB' => $vmdk_info->{'VmDiskFileInfo'}->capacityKb()
	);
	
	my $vm_config_spec = VirtualMachineConfigSpec->new(
		'deviceChange' => [
			VirtualDeviceConfigSpec->new(
				'operation' => VirtualDeviceConfigSpecOperation->new('add'),
				'device' => $disk,
			)
		]
	);
	
	return { 'vm_view' => $v, 'vm_config_spec' => $vm_config_spec};
}

sub _reconfig_vm()
{
	my $self = shift;
	my $v = shift;
	my $vm_config_spec = shift;
	
	eval
	{
		$v->ReconfigVM('spec' => $vm_config_spec);
	};
	
	$v->update_view_data();
	
	return $v || { 'vmapi_error_code' => '500', 'vmapi_error' => $@->{'fault_string'} || ${$@->detail}{'text'} };
}

sub _reconfig_vm_task()
{
	my $self = shift;
	my $v = shift;
	my $vm_config_spec = shift;
		
	my $task = undef;
	
	eval
	{
		$task = $v->ReconfigVM_Task('spec' => $vm_config_spec);
	};
	
	if($@)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => $@->{'fault_string'} || ${$@->detail}{'text'} };
	}
	
	return shift @{$self->mor_to_views($task)};
}

sub attach_vmdk
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $r = $self->_attach_vmdk_spec($args);
	
	return $r
		if($r->{'vmapi_error_code'});
		
	return $self->_reconfig_vm(
		$r->{'vm_view'},
		$r->{'vm_config_spec'}
	);
}

sub attach_vmdk_task
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $r = $self->_attach_vmdk_spec($args);
	
	return $r
		if($r->{'vmapi_error_code'});
		
	return $self->_reconfig_vm_task(
		$r->{'vm_view'},
		$r->{'vm_config_spec'}
	);
}

sub _detach_vmdk_spec
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $vmdk_name = $args->{'vmdk_name'};
	
	my $result = {};
	
	my $v = $self->find_entity_view(
		'view_type' => 'VirtualMachine',
		'filter' => { 'config.name' => $args->{'vm_name'} },
	);
	
	if(!$v)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'VM not found' };
	}
	
	my $devices = $v->config()->hardware()->device();
	my $disk = shift @{[ grep {
		if(ref($_) eq 'VirtualDisk')
		{
			my $re = $vmdk_name;
			$re =~ s/^\[(.+)\]/\\[$1\\]/;
			$re = qr/$re/;
		 	
		 	$_->backing()->fileName() =~ /$re/
		}
	} @$devices ]};
	
	if(!$disk)
	{
		return { 'vmapi_error_code' => '500', 'vmapi_error' => 'Disk not found' };
	}
	
	my $vm_config_spec = VirtualMachineConfigSpec->new(
		'deviceChange' => [
			VirtualDeviceConfigSpec->new(
				'operation' => VirtualDeviceConfigSpecOperation->new('remove'),
				'device' => $disk,
			)
		]
	);
	
	if($args->{'destroy'})
	{
		$vm_config_spec->{'deviceChange'}->[0]->{'fileOperation'} =  VirtualDeviceConfigSpecFileOperation->new('destroy');
	}
	
	return { 'vm_view' => $v, 'vm_config_spec' => $vm_config_spec};
}

sub detach_vmdk
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $r = $self->_detach_vmdk_spec($args);
	
	return $r
		if($r->{'vmapi_error_code'});
		
	return $self->_reconfig_vm(
		$r->{'vm_view'},
		$r->{'vm_config_spec'}
	);
}

sub detach_vmdk_task
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $r = $self->_detach_vmdk_spec($args);
	
	return $r
		if($r->{'vmapi_error_code'});
		
	return $self->_reconfig_vm_task(
		$r->{'vm_view'},
		$r->{'vm_config_spec'}
	);
}

sub screen
{
	my $self = shift;
	my $args = ref($_[0]) eq 'HASH' ? shift : { @_ };
	
	my $server;
	my $id;
	
	if(my $view = $args->{'view'})
	{
		print STDERR Data::Dumper::Dumper $view->summary()->vm(), $id = $view->summary()->vm()->value();
		$server = $self->mor_to_views($view->runtime()->host())->[0]->name();
	}
	
	print STDERR Data::Dumper::Dumper my $url = sprintf(
		'%s://%s:%s@%s/screen?id=%d',
		Opts::get_option('protocol'),
		($server) ? 'root' : Opts::get_option('username'),
		($server) ? 'pa66w9rd-' : Opts::get_option('password'),
		$server || Opts::get_option('server'),
		$id
	);
	
	require LWP::Simple;
	
	return LWP::Simple::get($url);
}


sub DESTROY
{
	my $self = shift;
	
	$self->logout();
}

1;

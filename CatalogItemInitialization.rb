#
# Description: This method Performs the following functions:
# 1. YAML load the Service Dialog Options from @task.get_option(:parsed_dialog_options))
# 2. Set the name of the service
# 3. Set tags on the service
# 5. Override miq_provision task with any options and tags
# Important - The dialog_parser automate method has to run prior to this in order to populate the dialog information.
#
 require 'miq-password'
def log_and_update_message(level, msg, update_message = false)
  $evm.log(level, "#{msg}")
  @task.message = msg if @task && (update_message || level == 'error')
end

# Loop through all tags from the dialog and create the categories and tags automatically
def create_tags(category, single_value, tag)
  # Convert to lower case and replace all non-word characters with underscores
  category_name = category.to_s.downcase.gsub(/\W/, '_')
  tag_name = tag.to_s.downcase.gsub(/\W/, '_')
  # if the category exists else create it
  unless $evm.execute('category_exists?', category_name)
    log_and_update_message(:info, "Creating Category: {#{category_name} => #{category}}")
    $evm.execute('category_create', :name         => category_name,
                                    :single_value => single_value,
                                    :description  => "#{category}")
  end
  # if the tag exists else create it
  return if $evm.execute('tag_exists?', category_name, tag_name)
  log_and_update_message(:info, "Creating tag: {#{tag_name} => #{tag}}")
  $evm.execute('tag_create', category_name, :name => tag_name, :description => "#{tag}")
end

def create_category_and_tags_if_necessary(dialog_tags_hash)
  dialog_tags_hash.each do |category, tag|
    Array.wrap(tag).each do |tag_entry|
      create_tags(category, true, tag_entry)
    end
  end
end

def override_service_name(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_name...", true)
  new_service_name = dialog_options_hash.fetch(:service_name, nil)
  new_service_name = "#{@service.name}-#{Time.now.strftime('%Y%m%d-%H%M%S')}" if new_service_name.blank?

  log_and_update_message(:info, "Service name: #{new_service_name}")
  @service.name = new_service_name
  log_and_update_message(:info, "Processing override_service_name...Complete", true)
end

def override_service_description(dialog_options_hash)
  log_and_update_message(:info, "Processing override_service_description...", true)
  new_service_description = dialog_options_hash.fetch(:service_description, nil)
  return if new_service_description.blank?

  log_and_update_message(:info, "Service description #{new_service_description}")
  @service.description = new_service_description
  log_and_update_message(:info, "Processing override_service_description...Complete", true)
end

def tag_service(dialog_tags_hash)
  return if dialog_tags_hash.nil?

  log_and_update_message(:info, "Processing tag service...", true)

  dialog_tags_hash.each do |key, value|
    log_and_update_message(:info, "Processing Tag Key: #{key.inspect}  value: #{value.inspect}")
    next if value.blank?
    get_service_tags(key.downcase, value)
  end
  log_and_update_message(:info, "Processing tag_service...Complete", true)
end

def get_service_tags(tag_category, tag_value)
  Array.wrap(tag_value).each do |tag_entry|
    assign_service_tag(tag_category, tag_entry)
  end
end

def assign_service_tag(tag_category, tag_value)
  $evm.log(:info, "Adding tag category: #{tag_category} tag: #{tag_value} to Service: #{@service.name}")
  @service.tag_assign("#{tag_category}/#{tag_value}")
end

def get_vm_name(dialog_options_hash, prov)
  log_and_update_message(:info, "Processing get_vm_name", true)
  new_vm_name = dialog_options_hash.fetch(:vm_name, nil) || dialog_options_hash.fetch(:vm_target_name, nil)

  new_vm_name = prov.get_option(:vm_target_name) if new_vm_name.blank?

  dialog_options_hash[:vm_target_name] = new_vm_name
  dialog_options_hash[:vm_target_hostname] = new_vm_name
  dialog_options_hash[:vm_name] = new_vm_name
  dialog_options_hash[:linux_host_name] = new_vm_name
  log_and_update_message(:info, "Processing get_vm_name...Complete", true)
end

def service_item_dialog_values(dialogs_options_hash)
  merged_options_hash = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  if dialogs_options_hash[0].nil?
    merged_options_hash = dialogs_options_hash[provision_index] || {}
  else
    merged_options_hash = dialogs_options_hash[0].merge(dialogs_options_hash[provision_index] || {})
  end
  merged_options_hash
end

def service_item_tag_values(dialogs_tags_hash)
  merged_tags_hash         = Hash.new { |h, k| h[k] = {} }
  provision_index = determine_provision_index

  # merge dialog_tag_0 stuff with current build
  if dialogs_tags_hash[0].nil?
    merged_tags_hash = dialogs_tags_hash[provision_index] || {}
  else
    merged_tags_hash = dialogs_tags_hash[0].merge(dialogs_tags_hash[provision_index] || {})
  end
  merged_tags_hash
end

def determine_provision_index
  service_resource = @task.service_resource
  if service_resource
    # Increment the provision_index number since the child resource starts with a zero
    provision_index = service_resource.provision_index ? service_resource.provision_index + 1 : 0
    log_and_update_message(:info, "Bundle --> Service name: #{@service.name}> provision_index: #{provision_index}")
  else
    provision_index = 1
    log_and_update_message(:info, "Item --> Service name: #{@service.name}> provision_index: #{provision_index}")
  end
  provision_index
end

def add_provision_tag(key, value, prov)
  log_and_update_message(:info, "Adding Tag: {#{key.inspect} => #{value.inspect}} to Provisioning id: #{prov.id}")
  prov.add_tag(key.to_s.downcase.gsub(/\W/, '_'), value.to_s.downcase.gsub(/\W/, '_'))
end

def get_provision_tags(key, value, prov)
  Array.wrap(value).each do |tag_entry|
    add_provision_tag(key, tag_entry.downcase, prov)
  end
end

def tag_provision_task(dialog_tags_hash, prov)
  dialog_tags_hash.each do |key, value|
    get_provision_tags(key, value, prov)
  end
end

def find_object_for(rsc_class, id_or_name)
  if /\d{13}/.match(id_or_name.to_s)
    # Looks like an ID
    obj = $evm.vmdb(rsc_class, id_or_name.to_s)
  else
    obj = $evm.vmdb(rsc_class).find_by_name(id_or_name.to_s)
  end
  $evm.log(:warn, "Couldn\'t find an object of class #{rsc_class} with an ID or name matching \'#{id_or_name}\'") if obj.nil?
  obj
end
  
def set_option_on_provision_task(dialog_options_hash, prov)
  # Cater for the fact that several of the provisioning task options have their own methods to set
  custom_methods = {
    :vm_notes => :set_vm_notes,
    :dvs => :set_dvs,
    :vlan => :set_vlan,
    :addr_mode => :set_network_address_mode
  }
  
  rsc_methods = {
    :placement_host_name => [[:set_host, 'Host']],
    :placement_ds_name => [[:set_storage, 'Storage']],
    :placement_cluster_name => [[:set_cluster, 'EmsCluster']],
    :placement_rp_name => [[:set_resource_pool, 'ResourcePool']],
    :placement_folder_name => [[:set_folder, 'EmsFolder']],
    :pxe_server_id => [[:set_pxe_server, 'PxeServer']],
    :pxe_image_id => [[:set_pxe_image, 'PxeImage'], [:set_windows_image, 'WindowsImage']],
    :customization_template_id => [[:set_customization_template, 'CustomizationTemplate']],
    :iso_image_id => [[:set_iso_image, 'IsoImage']],
    :placement_availability_zone => [[:set_availability_zone, 'AvailabilityZone']],
    :cloud_tenant => [[:set_cloud_tenant, 'CloudTenant']],
    :cloud_network => [[:set_cloud_network, 'CloudNetwork']],
    :cloud_subnet => [[:set_cloud_subnet, 'CloudSubnet']],
    :security_groups => [[:set_security_group, 'SecurityGroup']],
    :floating_ip_address => [[:set_floating_ip_address, 'FloatingIp']],
    :instance_type => [[:set_instance_type, 'Flavor']],
    :guest_access_key_pair => [[:set_guest_access_key_pair, 'AuthPrivateKey']]
  }
  
  dialog_options_hash.each do |key, value|
    if rsc_methods.keys.include?(key.to_sym)
      rsc_methods[key.to_sym].each do | rsc_method |
        rsc_obj = find_object_for(rsc_method[1], value)
        unless rsc_obj.nil?
          log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Provisioning id: #{prov.id} using #{rsc_method[0].to_s}") 
          output = prov.send(rsc_method[0], rsc_obj)
          $evm.log("info", "Output is #{output} for object #{rsc_obj}")
        end
      end
    elsif custom_methods.keys.include?(key.to_sym)
      log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Provisioning id: #{prov.id} using #{custom_methods[key.to_sym].to_s}")
      prov.send(custom_methods[key.to_sym], value)
    else
      log_and_update_message(:info, "Adding Option: {#{key} => #{value}} to Provisioning id: #{prov.id} using set_option")
      prov.set_option(key, value)
    end
  end
end

def pass_dialog_values_to_provision_task(provision_task, dialog_options_hash, dialog_tags_hash)
  provision_task.miq_request_tasks.each do |prov|
    log_and_update_message(:info, "Grandchild Task: #{prov.id} Desc: #{prov.description} type: #{prov.source_type}")
    get_vm_name(dialog_options_hash, prov)
    tag_provision_task(dialog_tags_hash, prov)
    set_option_on_provision_task(dialog_options_hash, prov)
  end
end

def pass_dialog_values_to_children(dialog_options_hash, dialog_tags_hash)
  @task.miq_request_tasks.each do |t|
    child_service = t.destination
    log_and_update_message(:info, "Child Service: #{child_service.name}")
    next if t.miq_request_tasks.nil?

    pass_dialog_values_to_provision_task(t, dialog_options_hash, dialog_tags_hash)
  end
end

def remove_service
  log_and_update_message(:info, "Processing remove_service...", true)
  if @service
    log_and_update_message(:info, "Removing Service: #{@service.name} id: #{@service.id} due to failure")
    @service.remove_from_vmdb
  end
  log_and_update_message(:info, "Processing remove_service...Complete", true)
end

def merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  merged_options_hash = service_item_dialog_values(dialog_options_hash)
  merged_tags_hash = service_item_tag_values(dialog_tags_hash)

  log_and_update_message(:info, "merged_options_hash: #{merged_options_hash.inspect}")
  log_and_update_message(:info, "merged_tags_hash: #{merged_tags_hash.inspect}")
  return merged_options_hash, merged_tags_hash
end

def dialog_parser_error
  log_and_update_message(:error, "Error loading dialog options")
  exit MIQ_ABORT
end

def yaml_data(option)
  log_and_update_message(:info, "OPTIONS Are #{option}")
  @task.get_option(option).nil? ? nil : YAML.load(@task.get_option(option))
end

def password_decryption(dialog_options_hash)

  pwd = dialog_options_hash.fetch(:"password::password", nil) 
  log_and_update_message('info', "Password is #{pwd}")
   decrypt_pwd = MiqPassword.decrypt(pwd) unless pwd.nil?
   log_and_update_message('info', "Decrypted Password is #{decrypt_pwd}")
   dialog_options_hash[:"password::dialog_password"] = decrypt_pwd
   dialog_options_hash[:"password::password"] = decrypt_pwd
  log_and_update_message('info', "Option Hash is #{dialog_options_hash}")
   @task.miq_request_tasks.each do |t|
    child_service = t.destination
    log_and_update_message(:info, "Child Service: #{child_service.name}")
    next if t.miq_request_tasks.nil?
    t.miq_request_tasks.each do |prov|
    prov.set_option(:"password::password", decrypt_pwd)
    prov.set_option(:"password::dialog_password", decrypt_pwd)
    pwd = prov.get_option(:"password::password")
    log_and_update_message('info', "Password is #{pwd}")
  end
 end
end  
def parsed_dialog_information
  dialog_options_hash = yaml_data(:parsed_dialog_options)
  dialog_tags_hash = yaml_data(:parsed_dialog_tags)
  if dialog_options_hash.blank? && dialog_tags_hash.blank?
    log_and_update_message(:info, "Instantiating dialog_parser to populate dialog options")
    $evm.instantiate('/Service/Provisioning/StateMachines/Methods/DialogParser')
    dialog_options_hash = yaml_data(:parsed_dialog_options)
    dialog_tags_hash = yaml_data(:parsed_dialog_tags)
    dialog_parser_error if dialog_options_hash.blank? && dialog_tags_hash.blank?
  end

  merged_options_hash, merged_tags_hash = merge_dialog_information(dialog_options_hash, dialog_tags_hash)
  return merged_options_hash, merged_tags_hash
end

begin
  @task = $evm.root['service_template_provision_task']

  @service = @task.destination
  log_and_update_message(:info, "Service: #{@service.name} Id: #{@service.id} Tasks: #{@task.miq_request_tasks.count}")
  dialog_options_hash, dialog_tags_hash = parsed_dialog_information
  password_decryption(dialog_options_hash)
  override_service_name(dialog_options_hash)

  override_service_description(dialog_options_hash)

  create_category_and_tags_if_necessary(dialog_tags_hash)

  tag_service(dialog_tags_hash)

  pass_dialog_values_to_children(dialog_options_hash, dialog_tags_hash)

rescue => err
  log_and_update_message(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  @task.finished("#{err}") if @task
  remove_service if @service
  exit MIQ_ABORT
end

module UserService
  class UsersImportJob < SharedModules::ApplicationJob
    def perform(document)
      file = download_file(document)
      xml_doc = Nokogiri::XML(File.open(file))
      UserService::RegisteredUser.import(xml_doc)
      document.update_attributes!(after_scan: nil)
    end
  end
end

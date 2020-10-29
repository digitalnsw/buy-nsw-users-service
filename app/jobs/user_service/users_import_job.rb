module UserService
  class UsersImportJob < SharedModules::ApplicationJob
    def perform(document)
      file = download_file(document)
      xml_doc = Nokogiri::XML(File.open(file))
      # Next two lines are commented, to prevent against accidental push of registered users
      UserService::RegisteredUser.import(xml_doc)
      document.update_attributes!(after_scan: nil)
    end
  end
end

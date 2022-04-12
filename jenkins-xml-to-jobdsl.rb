require 'nokogiri'
require 'pp'
require 'optparse'
require 'digest'

# Bucket to dump any helpers multiple classes may need.
module Helper

  # Escape Strings that are not valid groovy syntax.
  def escape str
    str.gsub(/\\/,"\\\\\\").gsub("'''", %q(\\\'\\\'\\\'))
  end

  def removeCarriage str
    str.tr "\r", "\n"
  end

  def formatText str
    if str =~ /false|true/
      truthy str
    else
      "'#{str}'"
    end
  end

  def truthy str
    str == 'true'
  end

  def toGroovyListOfStrings str
    str.split.map do |s|
      "'#{s}'"
    end.join ', '
  end

  # Example input:
  #   <properties>this=${thing}
  #   another=${one}
  #   duplicate=${one}
  #   duplicate=${one}</properties>
  def propertiesToMap propertyNode
    propertyNode
      .split("\n")
      .map{|prop| prop.split '='}
      .inject({}){|hash, arr| hash[arr[0]] = arr[1] ; hash}
      .to_a
      .map{|propKV| "'#{propKV[0]}':'''#{escape propKV[1]}'''"}
      .flatten
      .join ', '
  end

end

class SvnScmLocationNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    currentDepth = depth + indent
    svnurl=''
    node.elements.each do |i|
      case i.name
      when 'credentialsId', 'depthOption', 'local', 'ignoreExternalsOption'
        # do nothing
      when 'remote'
        svnurl = "#{i.text}"
      else
        puts "[-] ERROR SvnScmLocationNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "location('#{svnurl}') {"
    node.elements.each do |i|
      case i.name
      when 'remote'
        # do nothing
      when 'credentialsId'
          puts " " * currentDepth + "credentials('#{i.text}')"
      when 'depthOption'
          puts " " * currentDepth + "depth(javaposse.jobdsl.dsl.helpers.scm.SvnDepth.#{i.text.upcase})"
      when 'local'
          puts " " * currentDepth + "directory('#{i.text}')"
      when 'ignoreExternalsOption'
          puts " " * currentDepth + "ignoreExternals(#{i.text})"
      else
        puts "[-] ERROR SvnScmLocationNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class SvnScmDefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "svn {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'locations'
        i.elements.each do |j|
          case j.name
          when 'hudson.scm.SubversionSCM_-ModuleLocation'
            SvnScmLocationNodeHandler.new(j).process(job_name, currentDepth, indent)
          else
            puts "[-] ERROR SvnScmDefinitionNodeHandler unhandled element #{i}"
            pp j
          end
        end
      when 'excludedRegions', 'includedRegions', 'excludedUsers', 'excludedCommitMessages'
          if i.elements.any?
            patterns = "["
            i.elements.each do |p|
              patterns += "'#{p.text}',"
            end
            patterns[-1] = "]"
            puts " " * currentDepth + "#{i.name}(#{patterns})"
          end
      when 'excludedRevprop'
          puts " " * currentDepth + "excludedRevisionProperty('#{i.text}')"
      when 'workspaceUpdater'
          strategy = 'javaposse.jobdsl.dsl.helpers.scm.SvnCheckoutStrategy.'
          case i.attribute('class').value
          when 'hudson.scm.subversion.UpdateUpdater'
            strategy += 'UPDATE'
          when 'hudson.scm.subversion.CheckoutUpdater'
            strategy += 'CHECKOUT'
          when 'hudson.scm.subversion.UpdateWithCleanUpdater'
            strategy += 'UPDATE_WITH_CLEAN'
          when 'hudson.scm.subversion.UpdateWithRevertUpdater'
            strategy += 'UPDATE_WITH_REVERT'
          else
            puts "[-] ERROR SvnScmDefinitionNodeHandler unhandled element #{i}"
            pp i
          end
          puts " " * currentDepth + "checkoutStrategy(#{strategy})"
      when 'ignoreDirPropChanges', 'filterChangelog'
          # todo: figure out how to merge these into a configure {} block, since they aren't full supported yet
      else
        puts "[-] ERROR SvnScmDefinitionNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class MatrixAuthorizationNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "authorization {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'permission'
        if i.text.include? ":"
          p, u = i.text.split(":")
          puts " " * currentDepth + "permission(perm = '#{p}', user = '#{u}')"
        else
          puts "[-] ERROR MatrixAuthorizationNodeHandler unhandled element #{i}"
          pp i
        end
      else
        puts "[-] ERROR MatrixAuthorizationNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class RebuildNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "rebuild {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'autoRebuild', 'rebuildDisabled'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      else
        puts "[-] ERROR RebuildNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class LogRotatorNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "logRotator {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'daysToKeep', 'numToKeep', 'artifactDaysToKeep', 'artifactNumToKeep'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      else
        puts "[-] ERROR LogRotatorNodeHandler unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BuildDiscarderNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    currentDepth = depth
    node.elements.each do |i|
     if i.attribute('class')&.value == 'hudson.tasks.LogRotator'
       LogRotatorNodeHandler.new(i).process(job_name, currentDepth, indent)
     else
       puts "[-] ERROR BuildDiscarderNodeHandler unhandled element #{i}"
       pp i
     end
    end
  end
end

class ParametersNodeHandler < Struct.new(:node)
  def nvd(i)
    name = ""
    value = "null"
    description = "null"
    i.elements.each do |p|
      case p.name
      when "name"
        name = "#{p.text}"
      when "description"
        if (!p.text.to_s.strip.empty? && "#{p.text}" != "null")
          description = "'''#{p.text}'''"
        else
          description = "null"
        end
      when "defaultValue"
        value = "#{p.text}"
        if (!p.text.to_s.strip.empty? && ("#{p.text}" == "true" || "#{p.text}" == "false"))
          value = "#{p.text}"
        elsif (!p.text.to_s.strip.empty? && "#{p.text}" != "null")
          value = "'#{p.text}'"
        else
          value = "null"
        end
      when 'choices'
        if p.attribute('class')&.value == 'java.util.Arrays$ArrayList'
          value = "["
          p.elements.each do |k|
            case k.name
            when 'a'
              if k.attribute('class').value == 'string-array'
                value += k.elements.map{|s| "'#{s.text}'"}.join ', '
              end
            else
              puts "[-] ERROR ParametersNodeHandler 1 unhandled element #{k}"
              pp k
            end
          end
          value += "]"
        else
          puts "[-] ERROR ParametersNodeHandler 2 unhandled element #{p}"
          pp p
        end
      else
        #puts "[-] ERROR ParametersNodeHandler 3 unhandled element #{p}"
        #pp p
      end
    end
    return name, value, description
  end

  def process(job_name, depth, indent)
    param_block = []
    param_block << " " * depth + "parameters {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'com.seitenbau.jenkins.plugins.dynamicparameter.ChoiceParameterDefinition',
           'hudson.plugins.jira.versionparameter.JiraVersionParameterDefinition'
        # these cannot be defined in this scope. Have to be defined on /properties.
      when 'hudson.model.TextParameterDefinition'
        name, value, description = nvd(i)
        param_block << " " * currentDepth + "textParam('#{name}', #{value}, #{description})"
      when 'hudson.model.StringParameterDefinition'
        name, value, description = nvd(i)
        param_block << " " * currentDepth + "stringParam('#{name}', #{value}, #{description})"
      when 'hudson.model.BooleanParameterDefinition'
        name, value, description = nvd(i)
        param_block << " " * currentDepth + "booleanParam('#{name}', #{value}, #{description})"
      when 'hudson.model.ChoiceParameterDefinition'
        name, value, description = nvd(i)
        param_block << " " * currentDepth + "choiceParam('#{name}', #{value}, #{description})"
      when 'hudson.model.PasswordParameterDefinition'
        name, value, description = nvd(i)
        param_block << ""
        param_block << " " * currentDepth + "/* Found a Password Parameter of:"
        param_block << ""
        param_block << " " * currentDepth + "       Name: #{name}"
        param_block << " " * currentDepth + "       Value: #{value}"
        param_block << " " * currentDepth + "       description: #{description}"
        param_block << ""
        param_block << " " * currentDepth + "   These are no longer supported and you will need to configure something like:"
        param_block << " " * currentDepth + "   https://support.cloudbees.com/hc/en-us/articles/203802500-Injecting-Secrets-into-Jenkins-Build-Jobs */"
        param_block << ""
      else
        param_block << "[-] ERROR SvnScmLocationNodeHandler unhandled element #{pp i}"
      end
    end
    param_block << " " * depth + "}"
    return param_block
  end
end

class JiraVersionParameterDefinitionHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    innerNode = []
    node.elements.each do |i|
      case i.name
      when 'pattern'
        innerNode << {
          "'#{i.name}'" => i.elements.collect{|e| %W['#{e.name}'('#{escape e.text}')]}
        }
      else
        innerNode << "'#{i.name}'('#{i.text}')"
      end
    end

    unless innerNode.empty?
      ConfigureBlock.new([{
          "it / #{configurePath} / '#{node.name}'" => innerNode
        }],
        indent: indent
      ).save!
    end
  end

  def configurePath
    node
      .path
      .split('/')[2..4]
      .collect{|n| "'#{n}'"}
      .join ' / '
  end
end

class DynamicParameterHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "configure { project ->"

    currentDepth = depth + indent
    # Even though we are nested into properties already, we have to define it still.
    # The configure {} block in job dsl feels to be buggy and this works.
    puts " " * currentDepth + "project / 'properties' / 'hudson.model.ParametersDefinitionProperty' / 'parameterDefinitions' << '#{node.name}' {"
    node.elements.each do |i|
      case i.name
      when '__uuid', '__localBaseDirectory', '__remoteBaseDirectory'
        # nothing, dynamically created by the plugin.
      when '__remote', 'readonlyInputField'
        puts " " * (currentDepth + indent) + "'#{i.name}'(#{i.text})" unless i.text.empty?
      else
        puts " " * (currentDepth + indent) + "'#{i.name}'('''#{i.text}''')" unless i.text.empty?
      end
    end
    puts " " * currentDepth + "}"

    puts " " * depth + "}"
  end
end

class PropertiesNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    # hack... need to print parameter block outside of property block. :(
    parameter_node_block = nil
    puts " " * depth + "properties {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'com.sonyericsson.rebuild.RebuildSettings'
        RebuildNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.security.AuthorizationMatrixProperty'
        MatrixAuthorizationNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'org.jenkinsci.plugins.workflow.job.properties.BuildDiscarderProperty'
        BuildDiscarderNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.model.ParametersDefinitionProperty'
        i.elements.each do |p|
          case p.name
          when 'parameterDefinitions'

            # These are not supported in jobdsl so have to be configured via ConfigureBlock
            p.elements.each do |pelement|
              case pelement.name
              when 'com.seitenbau.jenkins.plugins.dynamicparameter.ChoiceParameterDefinition'
                DynamicParameterHandler.new(pelement).process(job_name, currentDepth, indent)
              when 'hudson.plugins.jira.versionparameter.JiraVersionParameterDefinition'
                JiraVersionParameterDefinitionHandler.new(pelement).process(job_name, currentDepth, indent)
              when 'hudson.model.PasswordParameterDefinition'
                # handled by ParametersNodeHandler
              end
            end

            # hack... should really be nested under properties {} but jobdsl doesnt support this yet
            parameter_node_block = ParametersNodeHandler.new(p).process(job_name, depth, indent)
          else
            puts "[-] ERROR PropertiesNodeHandler parameterDefinitions: unhandled element #{p}"
            pp p 
          end
        end
      when 'jenkins.model.BuildDiscarderProperty'
        BuildDiscarderNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'com.cloudbees.plugins.JobPrerequisites'
        ConfigureBlock.new([{
            "it / properties / '#{i.name}'" => [
              "'script'('''#{i.at_xpath("//#{i.name}/script")&.text}''')",
              "'interpreter'('#{i.at_xpath("//#{i.name}/interpreter")&.text}')"
            ]
          }],
          indent: indent
        ).save!
      when 'hudson.plugins.copyartifact.CopyArtifactPermissionProperty'
        CopyArtifactPermissionPropertyHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.jira.JiraProjectProperty'
        # @todo(ln) ignored
      when 'org.jenkinsci.plugins.workflow.job.properties.DisableConcurrentBuildsJobProperty'
        puts " " * currentDepth + 'disableConcurrentBuilds()'
      else
        puts "[-] ERROR PropertiesNodeHandler: unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
    if parameter_node_block
      parameter_node_block.each do |i|
        puts "#{i}"
      end
    end
  end
end

class CopyArtifactPermissionPropertyHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    innerNode = []

    node.elements.each do |i|
      case i.name
      when 'projectNameList'
        unless i.text.empty?
          nestedInnerNode = i.elements.map do |e|
                              "'#{e.name}'(#{formatText e.text})" unless e.text.empty?
                            end
          innerNode << { "'#{i.name}'" => nestedInnerNode }
        end
      else
        pp i
      end
    end

    ConfigureBlock.new([
      {
        "it / 'properties' / '#{node.name}'" => innerNode
      }
    ], indent: indent).save!
  end
end

class RemoteGitScmNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "remote {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'url'
        puts " " * currentDepth + "url('#{i.text}')"
      when 'credentialsId'
        puts " " * currentDepth + "credentials('#{i.text}')"
      when 'name', 'refspec'
        puts " " * currentDepth + "#{i.name}('#{i.text}')" unless i.text.empty?
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class GitScmExtensionsNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "extensions {"
    currentDepth = depth + indent
    puts " " * depth + "}"
  end
end

class GitScmDefinitionNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts " " * depth + "git {"
    currentDepth = depth + indent
    configureBlock = ConfigureBlock.new [], indent: indent, indent_times: (currentDepth / indent rescue 1)
    node.elements.each do |i|
      case i.name
      when 'configVersion'
        # nothing, generated by plugin
      when 'userRemoteConfigs'
        i.elements.each do |j|
          case j.name
          when 'hudson.plugins.git.UserRemoteConfig'
            RemoteGitScmNodeHandler.new(j).process(job_name, currentDepth, indent)
          else
            pp j
          end
        end
      when 'branches'
        i.elements.each do |j|
          case j.name
          when 'hudson.plugins.git.BranchSpec'
            branches = ""
            j.elements.each do |b|
              branches += "'#{b.text}',"
            end
            branches[-1] = ""
            puts " " * currentDepth + "branches(#{branches})"
          else
          end
        end
      when 'browser'
        puts " " * currentDepth + "browser {"
        if i.attribute('class').value == 'hudson.plugins.git.browser.Stash'
          puts " " * (currentDepth + indent) + "stash('#{i.at_xpath('//browser/url')&.text}')"
        else
          pp i
        end
        puts " " * currentDepth + "}"
      when 'gitTool', 'doGenerateSubmoduleConfigurations'
        configureBlock << "#{i.name}(#{formatText i.text})" unless i.text.empty? 
      when'submoduleCfg'
        # todo: not yet implemented
      when 'extensions'
        GitScmExtensionsNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        pp i
      end
    end
    puts configureBlock
    puts " " * depth + "}"
  end
end

class ScmDefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "scm {"
    currentDepth = depth + indent
    if node.attribute('class').value == 'hudson.plugins.git.GitSCM'
      GitScmDefinitionNodeHandler.new(node).process(job_name, currentDepth, indent)
    elsif node.attribute('class').value == 'hudson.scm.SubversionSCM'
      SvnScmDefinitionNodeHandler.new(node).process(job_name, currentDepth, indent)
    elsif node.attribute('class').value == 'hudson.scm.NullSCM'
    else
      pp node
    end
    puts " " * depth + "}"
  end
end

class CpsScmDefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "cpsScm {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'scm'
        ScmDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'scriptPath'
        puts " " * currentDepth + "scriptPath('#{i.text}')"
      when 'lightweight'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      else
        puts "[-] ERROR CpsScmNodeHandler: unhandled element #{i}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class CpsDefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "cps {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'script'
        txt = i.text.gsub(/\\/,"\\\\\\").gsub("'''", %q(\\\'\\\'\\\'))
        puts " " * currentDepth + "script('''\\\n#{txt}\n\'''\n)"
      when 'sandbox'
        puts " " * currentDepth + "sandbox(#{i.text})"
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class DefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "definition {"
    currentDepth = depth + indent
    if node.attribute('class').value == 'org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition'
      CpsScmDefinitionNodeHandler.new(node).process(job_name, currentDepth, indent)
    elsif node.attribute('class').value == 'org.jenkinsci.plugins.workflow.cps.CpsFlowDefinition'
      CpsDefinitionNodeHandler.new(node).process(job_name, currentDepth, indent)
    else
      pp node
    end
    puts " " * depth + "}"
  end
end

class TriggerDefinitionNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "triggers {"
    currentDepth = depth + indent
    node.elements.each do |trigger|
      case trigger.name
      when 'com.cloudbees.hudson.plugins.folder.computed.PeriodicFolderTrigger'
        trigger.elements.each do |prop|
          case prop.name
          when 'spec'
            #puts " " * currentDepth + "cron('#{prop.text}')"
          when 'interval'
            puts " " * currentDepth + "periodicFolderTrigger {\n" +
                   " " * (currentDepth + indent) + "interval('#{prop.text.to_i / 1000}s')\n" +
                   " " * currentDepth + "}"
            # https://issues.jenkins.io/browse/JENKINS-55429
            # STDERR.puts "[-] WARNING TriggerDefinitionNodeHandler: unhandled PeriodicFolderTrigger element #{prop}"
          else
            puts "[-] ERROR TriggerDefinitionNodeHandler: unhandled PeriodicFolderTrigger element #{prop}"
            pp trigger
          end
        end
      else
        puts "[-] ERROR TriggerDefinitionNodeHandler: unhandled element #{trigger}"
        pp trigger
      end
    end
    puts " " * depth + "}"
  end
end

class FlowDefinitionNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts "pipelineJob('#{job_name}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'actions'
      when 'description'
        if !(i.text.nil? || i.text.empty?)
          puts " " * currentDepth + "#{i.name}('''\\\n#{removeCarriage i.text}\n''')"
        end
      when 'keepDependencies', 'quietPeriod', 'disabled'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'displayName'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      when 'properties'
        PropertiesNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'definition'
        DefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'triggers'
        TriggerDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'authToken'
        puts " " * currentDepth + "authenticationToken('#{i.text}')"
      when 'concurrentBuild'
        puts " " * currentDepth + "concurrentBuild(#{i.text})"
      when 'logRotator'
        LogRotatorNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        puts "[-] ERROR FlowDefinitionNodeHandler: unhandled element #{i}"
        pp i
      end
    end
    ConfigureBlock.print
    puts "}"
  end
end



class TaskPropertiesHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    logText = "#{node.at_xpath('//hudson.plugins.postbuildtask.TaskProperties/logTexts/hudson.plugins.postbuildtask.LogProperties/logText')&.text}"
    script = node.at_xpath('//hudson.plugins.postbuildtask.TaskProperties/script')&.text
    script = script.gsub(/\\/,"\\\\\\").gsub("'''", %q(\\\'\\\'\\\'))
    escalate = node.at_xpath('//hudson.plugins.postbuildtask.TaskProperties/EscalateStatus')&.text
    runIfSuccessful = node.at_xpath('//hudson.plugins.postbuildtask.TaskProperties/RunIfJobSuccessful')&.text
    puts " " * depth + "task('#{logText.to_s.empty? ? ".*" : logText.delete!("\C-M")}','''\\\n#{script.delete!("\C-M")}\n''',#{escalate},#{runIfSuccessful})"
  end
end

class TasksNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    currentDepth = depth
    node.elements.each do |i|
      case i.name
      when 'hudson.plugins.postbuildtask.TaskProperties'
        TaskPropertiesHandler.new(i).process(job_name, currentDepth, indent)
      else
        pp i
      end
    end
  end
end

class PostBuildTaskNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "postBuildTask {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'tasks'
        TasksNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class ArchiverNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "archiveArtifacts {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'artifacts'
        puts " " * currentDepth + "pattern('#{i.text}')"
      when 'allowEmptyArchive'
        puts " " * currentDepth + "allowEmpty(#{i.text})"
      when 'onlyIfSuccessful', 'fingerprint', 'defaultExcludes'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'caseSensitive'
        #unsupported
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class SonarNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "sonar {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'branch'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      when 'mavenOpts', 'jobAdditionalProperties', 'settings', 'globalSettings', 'usePrivateRepository'
        # unsupported
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class IrcTargetsNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    node.elements.each do |i|
      case i.name
      when 'hudson.plugins.im.GroupChatIMMessageTarget'
        params = i.elements.collect {|e|
          "#{e.name}:#{formatText e.text}"
        }.join ', '
        puts " " * depth + "channel(#{params})"
      else
        pp i
      end
    end
  end

end

class IrcPublisherNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "irc {"
    currentDepth = depth + indent
    # ConfigureBlock has to be used here because jobdsl does not support
    # nesting configure within irc.
    configureBlock = ConfigureBlock.new [], indent: indent
    node.elements.each do |i|
      case i.name
      when 'buildToChatNotifier', 'channels'
        # dynamically created by IRC plugin, or cruft
      when 'targets'
        IrcTargetsNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'strategy'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      when 'notifyUpstreamCommitters'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'notifySuspects'
        puts " " * currentDepth + "notifyScmCommitters(#{i.text})"
      when 'notifyFixers'
        puts " " * currentDepth + "notifyScmFixers(#{i.text})"
      when 'notifyCulprits'
        puts " " * currentDepth + "notifyScmCulprits(#{i.text})"
      when 'notifyOnBuildStart'
        configureBlock << "(ircNode / '#{i.name}').setValue(#{i.text})"
      when 'matrixMultiplier'
        configureBlock << "(ircNode / '#{i.name}').setValue('#{i.text}')"
      else
        pp i
      end
    end

    unless configureBlock.empty?
      configureBlock.unshift "def ircNode = it / publishers / 'hudson.plugins.ircbot.IrcPublisher'"
      configureBlock.save!
    end

    puts " " * depth + "}"
  end
end


class ExtendedEmailNodeHandler < Struct.new(:node)
  def print_trigger_block(j, currentDepth, indent)
    j.elements.each do |k|
      case k.name
      when 'email'
        k.elements.each do |e|
          case e.name
          when 'attachmentsPattern'
            if !(e.text.nil? || e.text.empty?)
              puts " " * (currentDepth + indent * 2) + "attachmentPatterns('#{e.text}')"
            end
          when 'subject', 'recipientList'
            if !(e.text.nil? || e.text.empty?)
              puts " " * (currentDepth + indent * 2) + "#{e.name}('#{e.text}')"
            end
          when 'replyTo'
            puts " " * (currentDepth + indent * 2) + "replyToList('#{e.text}')"
          when 'compressBuildLog', 'attachBuildLog'
            puts " " * (currentDepth + indent * 2) + "#{e.name}(#{e.text})"
          when 'recipientProviders', 'contentType'
            # unsupported
          when 'body'
            puts " " * (currentDepth + indent * 2) + "content('''\\\n#{e.text}\n''')"
          else
            pp e
          end
        end
      when 'failureCount'
        #unsupported
      else
        pp k
      end
    end
  end

  def process(job_name, depth, indent)
    puts " " * depth + "extendedEmail {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'saveOutput'
        puts " " * currentDepth + "saveToWorkspace(#{i.text})"
      when 'replyTo'
        puts " " * currentDepth + "replyToList('#{i.text}')"
      when 'presendScript'
        puts " " * currentDepth + "preSendScript('#{i.text}')"
      when 'recipientList', 'contentType', 'defaultSubject'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      when 'defaultContent'
        puts " " * currentDepth + "#{i.name}('''\\\n#{i.text}\n''')"
      when 'attachBuildLog', 'compressBuildLog', 'disabled'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'attachmentsPattern'
        # unsupported
      when 'configuredTriggers'
        puts " " * currentDepth + "triggers {"
        i.elements.each do |j|
          case j.name
          when 'hudson.plugins.emailext.plugins.trigger.FixedTrigger'
            puts " " * (currentDepth + indent) + "fixed {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.FirstFailureTrigger'
            puts " " * (currentDepth + indent) + "firstFailure {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.FailureTrigger'
            puts " " * (currentDepth + indent) + "failure {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.SuccessTrigger'
            puts " " * (currentDepth + indent) + "success {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.AlwaysTrigger'
            puts " " * (currentDepth + indent) + "always {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.StillFailingTrigger'
            puts " " * (currentDepth + indent) + "stillFailing {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.StatusChangedTrigger'
            puts " " * (currentDepth + indent) + "statusChanged {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          when 'hudson.plugins.emailext.plugins.trigger.UnstableTrigger'
            puts " " * (currentDepth + indent) + "unstable {"
            print_trigger_block(j, currentDepth, indent)
            puts " " * (currentDepth + indent) + "}"
          else
            pp j
          end
        end
        puts " " * currentDepth + "}"
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class TapPublisherHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    innerNode = []
    node.elements.each do |i|
      innerNode << "'#{i.name}'('#{i.text}')" unless i.text.empty?
    end

    unless innerNode.empty?
      ConfigureBlock.new([{
          "it / 'publishers' / '#{node.name}'" => innerNode
        }],
        indent: indent
      ).save!
    end
  end
end

class JUnitResultArchiverHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    innerNode = []

    currentDepth = depth + indent

    node.elements.each do |i|
      case i.name
      when 'testResults'
        # Nothing, pulled out below because is in signature of archiveJunit method.
      when 'keepLongStdio'
        innerNode << ' ' * currentDepth + "retainLongStdout(#{i.text})" unless i.text.empty?
      when 'testDataPublishers'
        # TODO - don't have working example for this yet
      when 'healthScaleFactor'
        innerNode << ' ' * currentDepth + "#{i.name}(#{i.text})" unless i.text.empty?
      else
        pp i
      end
    end

    testResults = node.at_xpath("//publishers/#{node.name}/testResults")&.text
    archiveSig = ' ' * depth + "archiveJunit('#{testResults}')"
    if innerNode.empty?
      puts archiveSig
    else
      puts archiveSig + ' {'
      puts innerNode
      puts ' ' * depth + '}'
    end
  end
end

class MailerHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    recipients = node.at_xpath("//#{node.name}/recipients")&.text
    dontNotifyEveryUnstableBuild = node.at_xpath("//#{node.name}/dontNotifyEveryUnstableBuild")&.text
    sendToIndividuals = node.at_xpath("//#{node.name}/sendToIndividuals")&.text

    unless recipients.empty? || dontNotifyEveryUnstableBuild.empty? || sendToIndividuals.empty?
      puts " " * depth + "mailer('#{recipients}', #{dontNotifyEveryUnstableBuild}, #{sendToIndividuals})"
    end
  end
end

class PublishersNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "publishers {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'hudson.plugins.postbuildtask.PostbuildTask'
        PostBuildTaskNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.tasks.ArtifactArchiver'
        ArchiverNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'org.jenkinsci.plugins.stashNotifier.StashNotifier'
        puts " " * currentDepth + "stashNotifier()"
      when 'hudson.plugins.sonar.SonarPublisher'
        SonarNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.emailext.ExtendedEmailPublisher'
        ExtendedEmailNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.ircbot.IrcPublisher'
        IrcPublisherNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.tasks.BuildTrigger'
        projects = "['#{i.at_xpath('//hudson.tasks.BuildTrigger/childProjects')&.text}']"
        threshold = "'#{i.at_xpath('//hudson.tasks.BuildTrigger/threshold/name')&.text}'"
        puts " " * currentDepth + "downstream(#{projects}, #{threshold})"
      when 'hudson.plugins.performance.PerformancePublisher'
        PerformancePublisherNodeHandler.new(i).process(job_name, currentDepth+indent, indent)
      when 'hudson.plugins.sitemonitor.SiteMonitorRecorder'
        SiteMonitorRecorderHandler.new(i).process(job_name, currentDepth, indent)
      when 'org.tap4j.plugin.TapPublisher'
        TapPublisherHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.tasks.junit.JUnitResultArchiver'
        JUnitResultArchiverHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.tasks.Mailer'
        MailerHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.rubyMetrics.rcov.RcovPublisher'
        RcovPublisherHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.testng.Publisher'
        TestNgHandler.new(i).process(job_name, currentDepth, indent)
      when 'com.pocketsoap.ChatterNotifier'
        ChatterNotifierHandler.new(i).process(job_name, currentDepth, indent)
      when 'hudson.plugins.parameterizedtrigger.BuildTrigger'
        TriggerNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class ChatterNotifierHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    innerNode = []

    node.elements.each do |i|
      innerNode << "'#{i.name}'(#{formatText i.text})" unless i.text.empty?
    end

    ConfigureBlock.new([
      {
        "it / 'publishers' / '#{node.name}'" => innerNode
      }
    ], indent: indent).save!
  end
end

class TestNgHandler < Struct.new(:node)

  def process(job_name, depth, indent)
    reportFilenamePattern = node.at_xpath("//#{node.name}/reportFilenamePattern")&.text
    puts " " * depth + "archiveTestNG('#{reportFilenamePattern}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'reportFilenamePattern'
        # handled above
      when 'escapeTestDescp'
        puts " " * currentDepth + "escapeTestDescription(#{i.text})"
      when 'escapeExceptionMsg'
        puts " " * currentDepth + "escapeExceptionMessages(#{i.text})"
      when 'showFailedBuilds'
        puts " " * currentDepth + "showFailedBuildsInTrendGraph(#{i.text})"
      when 'unstableOnSkippedTests'
        puts " " * currentDepth + "markBuildAsUnstableOnSkippedTests(#{i.text})"
      when 'failureOnFailedTestConfig'
        puts " " * currentDepth + "markBuildAsFailureOnFailedConfiguration(#{i.text})"
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end

end

class RcovPublisherHandler < Struct.new(:node)

  def process(job_name, depth, indent)
    puts " " * depth + "rcov {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'reportDir'
        puts " " * currentDepth + "reportDirectory('#{i.text}')"
      when 'targets'
        handleTargets i, currentDepth
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end

  def handleTargets(i, depth)
    i.elements.each do |target|
      case target.name
      when 'hudson.plugins.rubyMetrics.rcov.model.MetricTarget'
        handleMetricTarget target, depth
      else
        pp target
      end
    end
  end

  def handleMetricTarget(i, depth)
    meth = ''
    signature = []

    i.elements.each do |target|
      case target.name
      when 'metric'
        case target.text
        when 'TOTAL_COVERAGE'
          meth = 'totalCoverage'
        when 'CODE_COVERAGE'
          meth = 'codeCoverage'
        else
          pp target
        end
      when 'healthy'
        signature[0] = target.text || 0
      when 'unhealthy'
        signature[1] = target.text || 0
      when 'unstable'
        signature[2] = target.text || 0
      else
        pp target
      end
    end

    unless meth.empty? && signature.empty?
      puts ' ' * depth + "#{meth}(#{signature.join ', '})"
    end
  end

end

class SiteMonitorRecorderHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    configureBlock = ConfigureBlock.new [], indent: indent
    node.elements.each do |i|
      case i.name
      when 'mSites'
        configureBlock << "def mSitesNode = it / publishers / '#{node.name}' / 'mSites'"
        i.elements.each do |mSite|
          innerNode = []
          mSite.elements.each do |s|
            case s.name
            when 'mUrl'
              innerNode << "'#{s.name}'('#{s.text}')"
            when 'timeout'
              innerNode << "'#{s.name}'(#{s.text})"
            when 'successResponseCodes'
              srcsInnerNode = []
              s.elements.each do |sInner|
                case sInner.name
                when 'int'
                  srcsInnerNode << "'#{sInner.name}'(#{sInner.text})"
                else
                  pp sInner
                end
              end
              innerNode << { "'#{s.name}'" => srcsInnerNode }
            end
          end

          unless innerNode.empty?
            configureBlock << { "mSitesNode << '#{mSite.name}'" => innerNode }
          end
        end
      end
    end
    configureBlock.save!
  end
end

class PerformancePublisherNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    innerNode = []

    node.elements.each do |i|
      case i.name
      when 'errorFailedThreshold', 'errorUnstableThreshold', 'relativeFailedThresholdPositive',
           'relativeFailedThresholdNegative', 'relativeUnstableThresholdPositive', 'relativeUnstableThresholdNegative',
           'nthBuildNumber', 'configType', 'modeOfThreshold', 'compareBuildPrevious', 'modePerformancePerTestCase',
           'errorUnstableResponseTimeThreshold', 'modeRelativeThresholds', 'failBuildIfNoResultFile', 'modeThroughput',
           'modeEvaluation', 'ignoreFailedBuilds', 'ignoreUnstableBuilds', 'persistConstraintLog'
        innerNode << "#{i.name} '#{i.text}'"
      when 'parsers'
        innerParsers = []
        i.elements.each do |inner|
          case inner.name
          when 'hudson.plugins.performance.JMeterParser'
            innerParsers << {
              "'#{inner.name}'" => inner.elements.collect do |ie|
                                     "'#{ie.name}'('#{ie.text}')"
                                   end
            }
          else
            pp i
          end
        end
        innerNode << {"'parsers'" => innerParsers}
      else
        pp i
      end
    end

    unless innerNode.empty?
      ConfigureBlock.new([{
          "it / publishers / '#{node.name}' <<" => innerNode
        }],
        indent: indent
      ).save!
    end
  end
end

class GoalsNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    node.children.each do |i|
      puts " " * depth + "goals('#{i.text}')"
    end
  end
end

class ArtifactNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "artifact {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'groupId', 'artifactId'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BlockNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "block {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'buildStepFailureThreshold'
        puts " " * currentDepth + "buildStepFailure('#{i.at_xpath('//buildStepFailureThreshold/name')&.text}')"
      when 'unstableThreshold'
        puts " " * currentDepth + "unstable('#{i.at_xpath('//unstableThreshold/name')&.text}')"
      when 'failureThreshold'
        puts " " * currentDepth + "failure('#{i.at_xpath('//failureThreshold/name')&.text}')"
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class TriggerNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts " " * depth + "downstreamParameterized {"
    projects = node.at_xpath('//configs/*/projects')&.text.split(',').map{|s|"'#{s}'"}.join(',')
    nestedDepth = depth + indent
    puts " " * nestedDepth + "trigger([#{projects}]) {"
    currentDepth = nestedDepth + indent
    node.elements.each do |i|
      case i.name
      when 'configs'
        i.elements.each do |j|
          case j.name
          when 'hudson.plugins.parameterizedtrigger.BlockableBuildTriggerConfig'
            j.elements.each do |k|
              case k.name
              when 'configs', 'projects'
                # intentionally ignored
              when 'condition'
                #puts " " * currentDepth + "#{k.name}('#{k.text}')"
              when 'triggerWithNoParameters', 'buildAllNodesWithLabel'
                #puts " " * currentDepth + "#{k.name}(#{k.text})"
              when 'block'
                BlockNodeHandler.new(k).process(job_name, currentDepth, indent)
              else
                pp k
              end
            end
          when 'hudson.plugins.parameterizedtrigger.BuildTriggerConfig'
            j.elements.each do |k|
              case k.name
              when 'projects'
                # handled at beginning of method
              when 'configs'
                k.elements.each do |l|
                  case l.name
                  when 'hudson.plugins.parameterizedtrigger.PredefinedBuildParameters'
                    l.elements.each do |m|
                      case m.name
                      when 'properties'
                        puts " " * currentDepth + "predefinedProps(#{propertiesToMap m.text})" unless i.text.empty?
                      else
                        pp m
                      end
                    end
                  else
                    pp l
                  end
                end
              when 'condition'
                puts " " * currentDepth + "#{k.name}('#{k.text}')"
              when 'triggerWithNoParameters'
                puts " " * currentDepth + "#{k.name}(#{truthy k.text})"
              else
                pp k
              end
            end
          else
            pp j.name
          end
        end
      else
        pp i
      end
    end
    puts " " * nestedDepth + "}"
    puts " " * depth + "}"
  end
end

class BuildersNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    currentDepth = depth
    node.elements.each do |i|
      case i.name
      when 'hudson.plugins.parameterizedtrigger.TriggerBuilder'
        puts " " * currentDepth + "steps {"
        TriggerNodeHandler.new(i).process(job_name, currentDepth, indent)
        puts " " * currentDepth + "}"
      when 'hudson.tasks.Shell'
        puts " " * currentDepth + "steps {"
	txt = i.at_xpath('//hudson.tasks.Shell/command')&.text
        txt = txt&.gsub(/\\/,"\\\\\\").gsub("'''", %q(\\\'\\\'\\\'))
        puts " " * (currentDepth + indent) + "shell('''\\\n#{txt}\n''')"
        puts " " * currentDepth + "}"
      when 'org.jvnet.hudson.plugins.SSHBuilder'
        puts " " * currentDepth + "steps {"
        puts " " * (currentDepth + depth) + "remoteShell('#{i.at_xpath("//#{i.name}/siteName")&.text}') {"
        puts " " * (currentDepth + depth + depth) + "command('''#{i.at_xpath("//#{i.name}/command")&.text}''')"
        puts " " * (currentDepth + depth) + "}"
        puts " " * currentDepth + "}"
      when 'hudson.tasks.Maven'
        puts " " * currentDepth + "steps {"
        MavenBuilderHandler.new(i).process(job_name, currentDepth + indent, indent)
        puts " " * currentDepth + "}"
      when 'hudson.plugins.copyartifact.CopyArtifact'
        puts " " * currentDepth + "steps {"
        CopyArtifactHandler.new(i).process(job_name, currentDepth + indent, indent)
        puts " " * currentDepth + "}"
      when 'hudson.tasks.Ant'
        puts " " * currentDepth + "steps {"
        AntHandler.new(i).process(job_name, currentDepth + indent, indent)
        puts " " * currentDepth + "}"
      else
        pp i
      end
    end
  end
end

class AntHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts " " * depth + "ant {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'targets'
        puts " " * currentDepth + "#{i.name}([#{toGroovyListOfStrings i.text}])" unless i.text.empty?
      when 'antName'
        puts " " * currentDepth + "antInstallation(#{formatText i.text})" unless i.text.empty?
      when 'buildFile'
        puts " " * currentDepth + "#{i.name}(#{formatText i.text})" unless i.text.empty?
      when 'properties'
        puts " " * currentDepth + "props(#{propertiesToMap i.text})" unless i.text.empty?
      when 'antOpts'
        puts " " * currentDepth + "javaOpts([#{toGroovyListOfStrings i.text}])" unless i.text.empty?
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end

end

class CopyArtifactHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    upstreamProject = node.at_xpath("//#{node.name}/project")&.text
    puts " " * depth + "copyArtifacts('#{upstreamProject}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'doNotFingerprintArtifacts'
        puts " " * currentDepth + "fingerprintArtifacts(#{! truthy i.text})" unless i.text.empty?
      when 'excludes'
        puts " " * currentDepth + "excludePatterns(#{toGroovyListOfStrings i.text})" unless i.text.empty?
      when 'target'
        puts " " * currentDepth + "targetDirectory(#{formatText i.text})" unless i.text.empty?
      when 'selector'
        buildSelector i, currentDepth, indent
      when 'filter'
        puts " " * currentDepth + "includePatterns(#{toGroovyListOfStrings i.text})" unless i.text.empty?
      when 'project'
        # handled above
      else
        pp i
      end
    end
    puts " " * depth + "}"
  end

  def buildSelector currentNode, depth, indent
    puts " " * depth + "buildSelector {"
    currentDepth = depth + indent
    case currentNode.attribute('class').value
    when 'hudson.plugins.copyartifact.StatusBuildSelector'
      stable = currentNode.at_xpath("//#{currentNode.name}/stable")&.text
      puts " " * currentDepth + "latestSuccessful(#{truthy stable})"
    end
    puts " " * depth + "}"
  end

end

class MavenBuilderHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    innerNode = []
    currentDepth = depth + indent
    configureBlock = ConfigureBlock.new [], indent: indent, indent_times: (currentDepth / indent rescue 1)

    node.elements.each do |i|
      case i.name
      when 'properties'
        i.text.split("\n").each do |property|
          key, value = *property.split('=')
          innerNode << ' ' * currentDepth + "property('#{key}', '#{value}')"
        end
      when 'usePrivateRepository'
        configureBlock << "'#{i.name}'(#{i.text})" unless i.text.empty?
      when 'testDataPublishers'
        # TODO - don't have working example for this yet
      when 'settings'
        next if i.text.empty?
        path = i.at_xpath("//builders/#{node.name}/#{i.name}/path")&.text
        configureBlock << {"it / '#{i.name}'(class: '#{i[:class]}')" => ["'path'('#{path}')"]}
      when 'globalSettings'
        next if i.text.empty?
        path = i.at_xpath("//builders/#{node.name}/#{i.name}/path")&.text
        configureBlock << {"it / '#{i.name}'(class: 'jenkins.mvn.FilePathGlobalSettingsProvider')" => ["'path'('#{path}')"]}
      when 'targets'
        innerNode << ' ' * currentDepth + "goals('#{i.text}')" unless i.text.empty?
      when 'pom'
        innerNode << ' ' * currentDepth + "rootPOM('#{i.text}')" unless i.text.empty?
      when 'mavenName'
        innerNode << ' ' * currentDepth + "mavenInstallation('#{i.text}')" unless i.text.empty?
      else
        pp i
      end
    end

    unless innerNode.empty?
      puts ' ' * depth + "maven {"
      puts innerNode
      puts configureBlock unless configureBlock.empty?
      puts ' ' * depth + '}'
    end
  end
end

class MavenDefinitionNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts "mavenJob('#{job_name}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'actions', 'reporters', 'buildWrappers', 'prebuilders', 'postbuilders',
           'aggregatorStyleBuild', 'ignoreUpstremChanges', 'processPlugins', 'mavenValidationLevel'
        # todo: not yet implemented
      when 'description'
        if !(i.text.nil? || i.text.empty?)
          puts " " * currentDepth + "#{i.name}('''\\\n#{removeCarriage i.text}\n''')"
        end
      when 'properties'
        PropertiesNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'definition'
        DefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'triggers'
        TriggerDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'authToken'
        puts " " * currentDepth + "authenticationToken(token = '#{i.text}')"
      when 'mavenOpts', 'rootPOM', 'customWorkspace'
        puts " " * currentDepth + "#{i.name}('#{i.text}')"
      when 'keepDependencies', 'concurrentBuild', 'disabled', 'fingerprintingDisabled',
           'runHeadless', 'resolveDependencies', 'siteArchivingDisabled', 'archivingDisabled',
           'incrementalBuild', 'quietPeriod'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'goals'
        GoalsNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'publishers'
        PublishersNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'scm'
        ScmDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'canRoam', 'assignedNode'
        if i.name == 'canRoam' and i.text == 'true'
          puts " " * currentDepth + "label()"
        elsif i.name == 'assignedNode'
          puts " " * currentDepth + "label('#{i.text}')"
        end
      when 'blockBuildWhenDownstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnDownstreamProjects()"
        end
      when 'blockBuildWhenUpstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnUpstreamProjects()"
        end
      when 'disableTriggerDownstreamProjects'
        puts " " * currentDepth + "disableDownstreamTrigger(#{i.text})"
      when 'blockTriggerWhenBuilding'
        # todo: do this when jobdsl supports it
      when 'settings', 'globalSettings'
        # todo: is this necessary?
      when 'rootModule'
        # todo: is this necessary?
      when 'runPostStepsIfResult'
        puts " " * currentDepth + "postBuildSteps('#{i.at_xpath('//runPostStepsIfResult/name')&.text}') {"
        puts " " * currentDepth + "}"
      else
        pp i
      end
    end
    ConfigureBlock.print
    puts "}"
  end
end

def quoteEmptyString(s)
  s == '' ? "''" : s
end

class BBSCMSourceTraitsHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + " traits {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'com.cloudbees.jenkins.plugins.bitbucket.BranchDiscoveryTrait'
        puts " " * currentDepth + "bitbucketBranchDiscovery {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'strategyId'
            puts " " * currentDepth + " #{ii.name}(#{ii.text})" # @todo(ln) symbolicIds option EXCLUDE_BRANCHES_FILED_AS_PRS = 1
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler BranchDiscoveryTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'com.cloudbees.jenkins.plugins.bitbucket.OriginPullRequestDiscoveryTrait'
        puts " " * currentDepth + "bitbucketPullRequestDiscovery {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'strategyId'
            puts " " * currentDepth + " #{ii.name}(#{ii.text})" # @todo(ln) symbolicIds option MERGE_WITH_TARGET_BRANCH_REVISION = 1
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler OriginPullRequestDiscoveryTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'jenkins.scm.impl.trait.WildcardSCMHeadFilterTrait' 
        puts " " * currentDepth + "headWildcardFilter {"
        currentDepth += indent
        i.elements.each do |ii|
          if !['includes', 'excludes'].include?(ii.name)
            puts "[-] ERROR BBSCMSourceTraitsHandler WildcardSCMHeadFilterTrait: unhandled element #{ii.name}"
            pp ii
          end
          puts " " * currentDepth + " #{ii.name}('#{ii.text}')" 
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'com.cloudbees.jenkins.plugins.bitbucket.SSHCheckoutTrait' 
        puts " " * currentDepth + "bitbucketSshCheckout {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'credentialsId'
            puts " " * currentDepth + " #{ii.name}('#{ii.text}')" 
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler SSHCheckoutTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'jenkins.plugins.git.traits.CheckoutOptionTrait' 
        puts " " * currentDepth + "checkoutOptionTrait {"
        currentDepth += indent
        puts " " * currentDepth + "extension {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'extension'
            ii.attributes.each do |aa, vv|
              if !(aa == 'class' && vv.text == 'hudson.plugins.git.extensions.impl.CheckoutOption')
                puts "[-] ERROR BBSCMSourceTraitsHandler CheckoutOptionTrait extension: unhandled attribute #{aa}=#{vv}"
              end
              ii.elements.each do |cc|
                if !(cc.name == 'timeout')
                  puts "[-] ERROR BBSCMSourceTraitsHandler CheckoutOptionTrait extension #{aa}: unhandled element #{cc.name}=#{cc.text}"
                end
                puts " " * currentDepth + " #{cc.name}(#{cc.text})" 
              end
            end
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler CheckoutOptionTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'jenkins.plugins.git.traits.LocalBranchTrait' 
        puts " " * currentDepth + "localBranchTrait {"
        currentDepth += indent
        puts " " * currentDepth + "extension {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'extension'
            ii.attributes.each do |aa, vv|
              if !(aa == 'class' && vv.text == 'hudson.plugins.git.extensions.impl.LocalBranch')
                puts "[-] ERROR BBSCMSourceTraitsHandler LocalBranchTrait extension: unhandled attribute #{aa}=#{vv}"
              end
              ii.elements.each do |cc|
                if !(cc.name == 'localBranch')
                  puts "[-] ERROR BBSCMSourceTraitsHandler LocalBranchTrait extension #{aa}: unhandled element #{cc.name}=#{cc.text}"
                end
                puts " " * currentDepth + " #{cc.name}('#{cc.text}')" 
              end
            end
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler CheckoutOptionTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'jenkins.plugins.git.traits.CloneOptionTrait' 
        puts " " * currentDepth + "cloneOptionTrait {"
        currentDepth += indent
        puts " " * currentDepth + "extension {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'extension'
            ii.attributes.each do |aa, vv|
              if !(aa == 'class' && vv.text == 'hudson.plugins.git.extensions.impl.CloneOption')
                puts "[-] ERROR BBSCMSourceTraitsHandler CloneOptionTrait extension: unhandled attribute #{aa}=#{vv}"
              end
              ii.elements.each do |cc|
                if !['shallow', 'noTags', 'reference', 'timeout', 'depth', 'honorRefspec'].include? cc.name
                  puts "[-] ERROR BBSCMSourceTraitsHandler CloneOptionTrait extension #{aa}: unhandled element #{cc.name}=#{cc.text}"
                else
                  puts " " * currentDepth + " #{cc.name}(#{quoteEmptyString(cc.text)})"
                end
              end
            end
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler CloneOptionTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'com.cloudbees.jenkins.plugins.bitbucket.ForkPullRequestDiscoveryTrait'
        # https://issues.jenkins.io/browse/JENKINS-61119 Cannot configure Bitbucket ForkPullRequestDiscoveryTrait by using Job DSL dynamic API
        strategyId = trustClazz = nil
        i.elements.each do |ii|
          case ii.name
          when 'strategyId'
            strategyId = ii.text
          when 'trust'
            trustClazz = ii.attributes['class'].value
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler ForkPullRequestDiscoveryTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        fprdt = [
          "def traits = it / sources / data / 'jenkins.branch.BranchSource' / source / traits",
          "traits << 'com.cloudbees.jenkins.plugins.bitbucket.ForkPullRequestDiscoveryTrait' { "
        ]
        unless strategyId.nil?
          fprdt << " " * indent + "strategyId(#{strategyId})"
        end
        unless trustClazz.nil?
          fprdt << " " * indent + "trust(class: '#{trustClazz}')"
        end
        fprdt << "}"
        ConfigureBlock.new(fprdt, indent: indent).save!
=begin
        puts " " * currentDepth + "bitbucketForkDiscovery {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'strategyId'
            puts " " * currentDepth + "strategyId(#{ii.text})"
          when 'trust'
            clazz = ii.attributes['class'].value
            case clazz
            when 'com.cloudbees.jenkins.plugins.bitbucket.ForkPullRequestDiscoveryTrait$TrustTeamForks', 'com.cloudbees.jenkins.plugins.bitbucket.ForkPullRequestDiscoveryTrait$TrustNobody', 'com.cloudbees.jenkins.plugins.bitbucket.ForkPullRequestDiscoveryTrait$TrustEveryone'
              puts " " * currentDepth + "trust(class: '#{clazz}')"
            else
              puts "[-] ERROR BBSCMSourceTraitsHandler ForkPullRequestDiscoveryTrait: unhandled trust element #{clazz}"
              pp ii
            end
          else
            puts "[-] ERROR BBSCMSourceTraitsHandler ForkPullRequestDiscoveryTrait: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
=end
      when 'com.cloudbees.jenkins.plugins.bitbucket.TagDiscoveryTrait'
        puts " " * currentDepth + "bitbucketTagDiscovery()"
        i.elements.each do |ii|
            puts "[-] ERROR BBSCMSourceTraitsHandler TagDiscoveryTrait: unhandled element #{ii.name}"
            pp ii
        end
      else
        puts "[-] ERROR BBSCMSourceTraitsHandler: unhandled element #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BitbucketSCMSourceHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "bitbucket {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'id', 'serverUrl', 'credentialsId', 'repoOwner', 'repository'
        puts " " * currentDepth + " #{i.name}('#{i.text}')"
      when 'traits'
        BBSCMSourceTraitsHandler.new(i).process(job_name, currentDepth, indent)
      else
        puts "[-] ERROR BitbucketSCMSourceHandler: unhandled element #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BBSCMChangeRequestBuildStrategyHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "buildChangeRequests {"
    currentDepth = depth + indent
    node.elements.each do |i|
      if !['ignoreTargetOnlyChanges', 'ignoreUntrustedChanges'].include? i.name
        puts "[-] ERROR BBBSCMChangeRequestBuildStrategyHandler: unhandled element #{i.name}=#{i.text}"
      end
      puts " " * currentDepth + " #{i.name}(#{i.text})"
    end
    puts " " * depth + "}"
  end
end

class BBSCMTagBuildStrategyHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "buildTags {"
    currentDepth = depth + indent
    node.elements.each do |i|
      if !['atLeastMillis', 'atMostMillis'].include? i.name
        puts "[-] ERROR BBBSCMCTagBuildBuildStrategyHandler: unhandled element #{i.name}=#{i.text}"
      end
      puts " " * currentDepth + " #{i.name}(#{i.text})"
    end
    puts " " * depth + "}"
  end
end

class BBSCMNamedBranchBuildStrategyHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts " " * depth + "buildNamedBranches {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'filters'
        puts " " * currentDepth + "filters {"
        currentDepth += indent

        i.elements.each do |ii|
          case ii.name
          when 'jenkins.branch.buildstrategies.basic.NamedBranchBuildStrategyImpl_-WildcardsNameFilter'
            puts " " * currentDepth + "wildcards {"
            currentDepth += indent
            ii.elements.each do |filter|
              puts " " * currentDepth + " #{filter.name}(#{formatText filter.text})"
            end
            puts " " * currentDepth + "}"
            currentDepth -= indent
          else
            puts "[-] ERROR BBBSCMNamedBranchBuildStrategyHandler filters: unhandled element #{ii.name}=#{ii.text}"
            pp ii
          end
        end
        puts " " * currentDepth + "}"
        currentDepth -= indent
      else
        puts "[-] ERROR BBBSCMNamedBranchBuildStrategyHandler: unhandled element #{i.name}=#{i.text}"
        pp i
      end
    end

    puts " " * depth + "}"
  end
end

class BBSCMAnyBranchBuildStrategyHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "buildAnyBranches {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'strategies'
        puts " " * currentDepth + "strategies {"
        currentDepth += indent
        i.elements.each do |ii|
          case ii.name
          when 'jenkins.branch.buildstrategies.basic.ChangeRequestBuildStrategyImpl'
            puts " " * currentDepth + "buildChangeRequests {"
            currentDepth += indent
            ii.elements.each do |iii|
              case iii.name
              when 'ignoreTargetOnlyChanges', 'ignoreUntrustedChanges'
                puts " " * currentDepth + " #{iii.name}('#{iii.text}')"
              else
                puts "[-] ERROR BBSCMAnyBranchBuildStrategyHandler strategies ChangeRequestBuildStrategy: unhandled element #{iii.name}"
                pp iii
              end
            end
            currentDepth -= indent
            puts " " * currentDepth + "}"
          when 'jenkins.branch.buildstrategies.basic.BranchBuildStrategyImpl'
            puts " " * currentDepth + "buildRegularBranches()"
            ii.elements.each do |iii|
                puts "[-] ERROR BBSCMAnyBranchBuildStrategyHandler strategies BranchBuildStrategy: unhandled element #{iii.name}"
                pp iii
            end
          when 'jenkins.branch.buildstrategies.basic.TagBuildStrategyImpl'
            puts " " * currentDepth + "buildTags {"
            currentDepth += indent
            ii.elements.each do |iii|
              case iii.name
              when 'atLeastMillis', 'atMostMillis'
                puts " " * currentDepth + " #{iii.name}('#{iii.text}')"
              else
                puts "[-] ERROR BBSCMAnyBranchBuildStrategyHandler strategies TagBuildStrategy: unhandled element #{iii.name}"
                pp iii
              end
            end
            currentDepth -= indent
            puts " " * currentDepth + "}"
          else
            puts "[-] ERROR BBSCMAnyBranchBuildStrategyHandler strategies: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      else
        puts "[-] ERROR BBSCMAnyBranchBuildStrategyHandler: unhandled alram #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BBSCMBuildStrategiesHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "buildStrategies {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'jenkins.branch.buildstrategies.basic.AnyBranchBuildStrategyImpl'
        BBSCMAnyBranchBuildStrategyHandler.new(i).process(job_name, currentDepth, indent)
      when 'jenkins.branch.buildstrategies.basic.ChangeRequestBuildStrategyImpl'
        BBSCMChangeRequestBuildStrategyHandler.new(i).process(job_name, currentDepth, indent)
      when 'jenkins.branch.buildstrategies.basic.NamedBranchBuildStrategyImpl'
        BBSCMNamedBranchBuildStrategyHandler.new(i).process(job_name, currentDepth, indent)
      when 'jenkins.branch.buildstrategies.basic.TagBuildStrategyImpl'
        BBSCMTagBuildStrategyHandler.new(i).process(job_name, currentDepth, indent)
      else
        puts "[-] ERROR BBSCMBuildStrategiesHandler: unhandled strategy #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class BranchSourceNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "branchSource {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'source'
        puts " " * currentDepth + "source {"
        currentDepth += indent
        clazz = i.attributes()['class'].value
        case clazz
        when 'com.cloudbees.jenkins.plugins.bitbucket.BitbucketSCMSource'
          BitbucketSCMSourceHandler.new(i).process(job_name, currentDepth, indent)
        else
          puts "[-] ERROR BranchSourceNodeHandler: unhandled branchSource class #{clazz}"
          pp i
        end
        currentDepth -= indent
        puts " " * currentDepth + "}"
      when 'buildStrategies'
        BBSCMBuildStrategiesHandler.new(i).process(job_name, currentDepth, indent)
      when 'strategy'
        i.attributes.each do |aa, vv|
          case aa
          when 'class'
            if vv.value != 'jenkins.branch.DefaultBranchPropertyStrategy'
              puts "[-] ERROR BranchSourceNodeHandler strategy class: unhandled value #{vv}"
              pp vv
            end
          else
            puts "[-] ERROR BranchSourceNodeHandler strategy unhandled attr: #{aa}"
            pp aa
          end
        end
        i.elements.each do |ii|
          case ii.name
          when 'properties'
            ii.attributes.each do |aa, vv|
              if !(aa == 'class' && vv.value == 'empty-list')
                puts "[-] ERROR BranchSourceNodeHandler strategy properties: unhandled attribute #{aa}=#{vv}"
                pp ii
              end
            end
          else
            puts "[-] ERROR BranchSourceNodeHandler strategy: unhandled element #{ii.name}"
            pp ii
          end
        end
      else
        puts "[-] ERROR BranchSourceNodeHandler: unhandled element #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class SourcesNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    puts " " * depth + "branchSources {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'data'
        i.elements.each do |ii|
          case ii.name
          when 'jenkins.branch.BranchSource'
            BranchSourceNodeHandler.new(ii).process(job_name, currentDepth, indent)
          else
            puts "[-] ERROR SourcesNodeHandler data: unhandled element #{ii.name}"
          end
        end
      when 'owner'
        # @todo(ln) detect unhandled content
      else
        puts "[-] ERROR SourcesNodeHandler: unhandled element #{i.name}"
        pp i
      end
    end
    puts " " * depth + "}"
  end
end

class FactoryNodeHandler < Struct.new(:node)
  def process(job_name, depth, indent)
    currentDepth = depth + indent 
    puts " " * depth + "factory {\n" + " " * currentDepth + "workflowBranchProjectFactory {"
    currentDepth += indent 
    node.elements.each do |i|
      case i.name
      when 'scriptPath'
        puts " " * currentDepth + "scriptPath('#{i.text}')"
      when 'owner'
        i.attributes.each do |aa, vv|
          if !(aa == 'class' && vv.value == 'org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject') && 
              !(aa == 'reference' && vv.value == '../..')
            puts "[-] ERROR FactoryNodeHandler owner: unhandled attribute #{aa}=#{vv}"
            pp vv
          end
        end
      else
        puts "[-] ERROR FactoryNodeHandler: unhandled element #{i.name}"
        pp i
      end
    end
    currentDepth -= indent
    puts " " * currentDepth + "}"
    puts " " * depth + "}"
  end
end

class WorkflowMultiBranchProjectHandler < Struct.new(:node)
  include Helper

  def process(folder_name, job_name, depth, indent)
    puts "multibranchPipelineJob('#{folder_name}/#{job_name}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'folderViews'
      when 'healthMetrics'
      when 'icon'
      when 'properties'

      when 'actions'
        if !i.text.empty?
            puts "[-] ERROR WorkflowMultiBranchProjectHandler actions: unhandled content"
            pp i
        end
      when 'displayName'
        if !(i.text.nil? || i.text.empty?)
          puts " " * currentDepth + "#{i.name}('#{removeCarriage i.text}')"
        end
      when 'factory'
        FactoryNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'sources'
        SourcesNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'description'
        if !(i.text.nil? || i.text.empty?)
          puts " " * currentDepth + "#{i.name}('''\\\n#{removeCarriage i.text}\n''')"
        end
      when 'keepDependencies', 'quietPeriod'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'orphanedItemStrategy'
        pruneDeadBranches = daysToKeep = numToKeep = abortBuilds = nil
        puts " " * currentDepth + "#{i.name} {\n"

        i.elements.each do |ii|
          case ii.name
          when 'pruneDeadBranches'
            pruneDeadBranches = true
          when 'daysToKeep'
            daysToKeep = ii.text
          when 'numToKeep'
            numToKeep = ii.text
          when 'abortBuilds'
            abortBuilds = ii.text
          else
            puts "[-] ERROR WorkflowMultiBranchProjectHandler orphanedItemStrategy: unhandled element #{ii.name}"
            pp ii
          end
        end
        currentDepth += indent
        if !pruneDeadBranches.nil?
          puts " " * currentDepth + "discardOldItems {"
          if !daysToKeep.nil? && daysToKeep != -1
            puts " " * (currentDepth + indent) + "daysToKeep(#{daysToKeep})"
          end
          if !numToKeep.nil? && numToKeep != -1
            puts " " * (currentDepth + indent) + "numToKeep(#{numToKeep})"
          end
          puts " " * currentDepth + "}\n"
        end
        currentDepth -= indent
        if !abortBuilds.nil?
          # not supported in JobDSL. maybe in settings? puts " " * (currentDepth + indent) + "abortBuilds(#{abortBuilds})"
        end
        puts " " * currentDepth + "}\n"
      when 'scm'
        ScmDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'canRoam', 'assignedNode'
        if i.name == 'canRoam' and i.text == 'true'
          puts " " * currentDepth + "label()"
        elsif i.name == 'assignedNode'
          puts " " * currentDepth + "label('#{i.text}')"
        end
#      when 'keepDependencies', 'concurrentBuild', 'disabled', 'fingerprintingDisabled',
#     'runHeadless', 'resolveDependencies', 'siteArchivingDisabled', 'archivingDisabled', 'incrementalBuild'
      when 'disabled'
        #disabled disabled
        if i.text != 'false'
          puts "[-] ERROR WorkflowMultiBranchProjectHandler orphanedItemStrategy: unhandled element #{i}"
        end
      when 'concurrentBuild'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'blockBuildWhenDownstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnDownstreamProjects()"
        end
      when 'blockBuildWhenUpstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnUpstreamProjects()"
        end
      when 'triggers'
        TriggerDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'publishers'
        PublishersNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'builders'
        BuildersNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'logRotator'
        LogRotatorNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        puts "[-] ERROR WorkflowMultiBranchProjectHandler: unhandled element #{i.text}"
        pp i
      end
    end
    ConfigureBlock.print
    puts "}"
  end
end

class FreestyleDefinitionNodeHandler < Struct.new(:node)
  include Helper

  def process(job_name, depth, indent)
    puts "freeStyleJob('#{job_name}') {"
    currentDepth = depth + indent
    node.elements.each do |i|
      case i.name
      when 'actions', 'buildWrappers'
        # todo: not yet implemented
      when 'description'
        if !(i.text.nil? || i.text.empty?)
          puts " " * currentDepth + "#{i.name}('''\\\n#{removeCarriage i.text}\n''')"
        end
      when 'keepDependencies', 'quietPeriod'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'properties'
        PropertiesNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'scm'
        ScmDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'canRoam', 'assignedNode'
        if i.name == 'canRoam' and i.text == 'true'
          puts " " * currentDepth + "label()"
        elsif i.name == 'assignedNode'
          puts " " * currentDepth + "label('#{i.text}')"
        end
#      when 'keepDependencies', 'concurrentBuild', 'disabled', 'fingerprintingDisabled',
#     'runHeadless', 'resolveDependencies', 'siteArchivingDisabled', 'archivingDisabled', 'incrementalBuild'
      when 'disabled', 'concurrentBuild'
        puts " " * currentDepth + "#{i.name}(#{i.text})"
      when 'blockBuildWhenDownstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnDownstreamProjects()"
        end
      when 'blockBuildWhenUpstreamBuilding'
        if i.text == 'true'
          puts " " * currentDepth + "blockOnUpstreamProjects()"
        end
      when 'triggers'
        TriggerDefinitionNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'publishers'
        PublishersNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'builders'
        BuildersNodeHandler.new(i).process(job_name, currentDepth, indent)
      when 'logRotator'
        LogRotatorNodeHandler.new(i).process(job_name, currentDepth, indent)
      else
        puts "[-] ERROR FreestyleDefinitionNodeHandler unhandled disabled=true #{i}"
        pp i
      end
    end
    ConfigureBlock.print
    puts "}"
  end
end

# Used to implement JobDSL's `configure {...}` type syntax. This class
# approaches this problem as if the configure block is an array of lines and
# each line can be either String, Hash, or Array. This is implemented this
# way due to the way that JobDSL's configure block works and its flexibility.
#
# See their docs for details on this:
# https://github.com/jenkinsci/job-dsl-plugin/wiki/The-Configure-Block
#
# This can be used like:
#
#   configureBlock = ConfigureBlock.new [], indent: 4
#   configureBlock << '// this would be the very first line within the configure block'
#   configureBlock << 'it / "this is the groovy reserved `it` to indicate the node we are on'
#   configureBlock << {'it / "can use a hash as well to describe inner blocks" <<' => ["'inner'('element')]}
#
#   configureBlock.save! #this will write `self` into the class constant that #print can use
#   ConfigureBlock.print #this will print all ConfigureBlock's that have been #save!'d
#
# Another way to do this is like:
#
#   arr = [
#     "def foo = it / 'inner' / 'xml'",
#     "(foo / 'bar').setValue('bazz')",
#     {
#       "it / 'using' / 'block' <<" => [
#         "'inner'('element')",
#         "'another'('element')",
#       ]
#     },
#     {
#       "it / 'another' / 'using' / 'block'" => [
#         {"'further'" => ["'nested'('element')"]},
#       ]
#     }
#   ]
#
#   configureBlock = ConfigureBlock.new arr, indent: 4
#   configureBlock.save!
#   ConfigureBlock.print
#
# You can also define multiple configure blocks just by instantiating a new one
# and calling #save! on that object.
class ConfigureBlock
  NOT_SO_CONSTANT_CONFIGURE_BLOCKS = []

  def self.print
    return if NOT_SO_CONSTANT_CONFIGURE_BLOCKS.empty?
    NOT_SO_CONSTANT_CONFIGURE_BLOCKS.each do |configureBlock|
      puts configureBlock
    end
  end

  def initialize arr = [], opts = {}
    @lines = arr
    @indent = opts[:indent] || 4
    @indent_times = opts[:indent_times] || 1
  end

  def << e
    @lines << e
  end

  def unshift e
    @lines.unshift e
  end

  def empty?
    @lines.empty?
  end

  def save!
    NOT_SO_CONSTANT_CONFIGURE_BLOCKS.push self
  end

  def to_s
    first = format 'configure {'
    middle = @lines.inject('') do |ret, line|
      ret = format line, @indent_times + 1
      ret
    end
    last = format '}'
    "#{first}#{middle}#{last}"
  end

  def format line, indent_times = @indent_times
    case line
    when String
      indention line, indent_times
    when Hash
      first = line.keys.first + ' {'
      indention first, indent_times
      format line.values.first, indent_times + 1
      indention '}', indent_times
    when Array
      line.each do |l|
        format l, indent_times
      end
    end
  end

  def indention line, indent_times = 1
    puts ' ' * @indent * indent_times + "#{line}\n"
  end

end

depth = 0
indent = 4

OptionParser.new do |opts|
  opts.banner = "Usage: ruby jenkins-xml-to-jobdsl.rb [OPTIONS] path/to/config.xml"

  opts.on(
    "-i indentation_level",
    "--indent=indentation_level",
    "Indentation level (default 4)",
  ) do |indentation_level|
    indent = indentation_level.to_i || 4
  end
end.parse!

f = ARGV.shift
ff = f
if !File.file?(f)
  exit 1
end

f = File.absolute_path(f)
d = File.dirname(f)
job = File.basename(f, '.xml')
basename = File.basename(f)
folder = f.split('/')[-2]
preamble = "# Converted from #{basename} #{Digest::SHA256.hexdigest File.read(f)}"

puts preamble

Nokogiri::XML::Reader(File.open(f)).each do |node|
  if node.name == 'flow-definition' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    FlowDefinitionNodeHandler.new(
      Nokogiri::XML(node.outer_xml).at('./flow-definition')
    ).process(job, depth, indent)
  elsif node.name == 'maven2-moduleset' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT
    MavenDefinitionNodeHandler.new(
      Nokogiri::XML(node.outer_xml).at('./maven2-moduleset')
    ).process(job, depth, indent)
  elsif node.name == 'project' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.depth == 0
    FreestyleDefinitionNodeHandler.new(
      Nokogiri::XML(node.outer_xml).at('./project')
    ).process(job, depth, indent)
  elsif node.name == 'org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject' && node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.depth == 0
    WorkflowMultiBranchProjectHandler.new(
      Nokogiri::XML(node.outer_xml).at('./org.jenkinsci.plugins.workflow.multibranch.WorkflowMultiBranchProject')
    ).process(folder, job, depth, indent)
  elsif node.node_type == Nokogiri::XML::Reader::TYPE_ELEMENT && node.depth == 0
    print '[-] ERROR unhandled: ' + node.name
  end
end


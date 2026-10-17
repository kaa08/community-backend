require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"
require "fileutils"

class DeployRollbackTest < Minitest::Test
  WORKFLOW = File.expand_path("../.github/workflows/ci-cd.yml", __dir__)
  OLD_IMAGE = "sha256:previous-image"
  NEW_IMAGE = "example.ecr/community:new-commit"

  # Fake external commands so the actual workflow script can run without AWS or Docker.
  FAKE_COMMAND = <<~'RUBY'
    require "json"
    state_file = ENV.fetch("DEPLOY_TEST_STATE")
    state_io = File.open(state_file, "r+")
    state_io.flock(File::LOCK_EX)
    state = JSON.parse(state_io.read)
    command = File.basename($0)
    state["calls"] << [command, *ARGV]
    mode = state.fetch("mode")
    status = 0

    case command
    when "flock"
      status = 1 if mode == "locked"
    when "aws"
      puts "temporary-token"
      status = 1 if mode == "login_failure"
    when "docker"
      case ARGV[0]
      when "ps"
        puts "container-id" if state["container"]
        status = 1 if mode == "inspect_failure"
      when "inspect"
        puts "sha256:previous-image"
      when "pull"
        status = 1 if mode == "pull_failure"
      when "rm"
        if mode == "remove_failure"
          status = 1
        else
          state["container"] = nil
        end
      when "run"
        image = ARGV.last
        state["container"] = image
        state["runs"] << image
        state["phase"] = image == "sha256:previous-image" ? "rollback" : "deploy"
        status = 1 if (state["phase"] == "deploy" && mode == "start_failure") ||
          (state["phase"] == "rollback" && mode == "rollback_start_failure")
      end
    when "curl"
      if state["phase"] == "initial"
        status = 1 if mode == "unhealthy_previous"
      elsif state["phase"] == "deploy"
        state["deploy_checks"] += 1
        status = 1 unless mode == "success" ||
          (mode == "delayed_success" && state["deploy_checks"] >= 3)
      elsif state["phase"] == "rollback"
        status = 1 if mode == "rollback_health_failure"
      end
      puts '{"status":"UP"}' if status == 0
    end

    state_io.rewind
    state_io.write(JSON.generate(state))
    state_io.truncate(state_io.pos)
    state_io.close
    exit status
  RUBY

  def setup
    workflow = YAML.load_file(WORKFLOW)
    step = workflow.fetch("jobs").fetch("build").fetch("steps").find do |entry|
      entry["name"] == "Deploy to EC2"
    end
    @script = step.fetch("with").fetch("script")
  end

  def simulate(mode, previous: true)
    Dir.mktmpdir("deploy-rollback-test") do |directory|
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      FileUtils.mkdir_p(File.join(directory, "dori"))
      File.write(File.join(directory, "dori", ".env"), "")
      %w[aws docker curl flock sleep].each do |command|
        path = File.join(bin, command)
        File.write(path, "#!#{RbConfig.ruby}\n" + FAKE_COMMAND)
        File.chmod(0755, path)
      end
      state_file = File.join(directory, "state.json")
      File.write(state_file, JSON.generate({
        mode: mode, container: previous ? OLD_IMAGE : nil,
        phase: "initial", calls: [], runs: [], deploy_checks: 0
      }))
      output, status = Open3.capture2e({
        "PATH" => "#{bin}:#{ENV.fetch('PATH')}",
        "HOME" => directory,
        "DEPLOY_TEST_STATE" => state_file,
        "AWS_REGION" => "ap-northeast-2",
        "ECR_REGISTRY" => "example.ecr",
        "ECR_REPOSITORY" => "community",
        "IMAGE_TAG" => "new-commit"
      }, "bash", "-s", stdin_data: @script)
      [JSON.parse(File.read(state_file)), status.exitstatus, output]
    end
  end

  def test_success_keeps_new_image_without_rollback
    state, status, output = simulate("success")
    assert_equal 0, status, output
    assert_equal [NEW_IMAGE], state["runs"]
    assert_equal NEW_IMAGE, state["container"]
    pull = state["calls"].index { |call| call[0..1] == %w[docker pull] }
    remove = state["calls"].index { |call| call[0..1] == %w[docker rm] }
    assert_operator pull, :<, remove
  end

  def test_startup_retries_before_success
    state, status, output = simulate("delayed_success")
    assert_equal 0, status, output
    assert_equal 3, state["deploy_checks"]
    assert_equal [NEW_IMAGE], state["runs"]
  end

  def test_preparation_failures_preserve_current_container
    %w[locked inspect_failure login_failure pull_failure unhealthy_previous remove_failure].each do |mode|
      state, status, output = simulate(mode)
      refute_equal 0, status, "#{mode}: #{output}"
      assert_equal OLD_IMAGE, state["container"], mode
      assert_empty state["runs"], mode
    end
  end

  def test_new_container_start_failure_restores_previous_image
    state, status, output = simulate("start_failure")
    refute_equal 0, status
    assert_equal [NEW_IMAGE, OLD_IMAGE], state["runs"]
    assert_equal OLD_IMAGE, state["container"]
    assert_includes output, "Rollback succeeded"
  end

  def test_health_failure_restores_previous_image_but_fails_deployment
    state, status, output = simulate("health_failure")
    refute_equal 0, status
    assert_equal 30, state["deploy_checks"]
    assert_equal [NEW_IMAGE, OLD_IMAGE], state["runs"]
    assert_equal OLD_IMAGE, state["container"]
    assert_includes output, "Rollback succeeded"
  end

  def test_rollback_failures_require_manual_recovery
    %w[rollback_start_failure rollback_health_failure].each do |mode|
      state, status, output = simulate(mode)
      refute_equal 0, status
      assert_equal [NEW_IMAGE, OLD_IMAGE], state["runs"]
      assert_includes output, "Rollback failed; manual recovery is required."
    end
  end

  def test_first_deployment_can_succeed
    state, status, output = simulate("success", previous: false)
    assert_equal 0, status, output
    assert_equal [NEW_IMAGE], state["runs"]
  end

  def test_first_deployment_failure_reports_missing_recovery_image
    state, status, output = simulate("health_failure", previous: false)
    refute_equal 0, status
    assert_nil state["container"]
    assert_equal [NEW_IMAGE], state["runs"]
    assert_includes output, "No previous image is available"
  end
end

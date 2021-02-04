# frozen_string_literal: true

# Note: This is _not_ an active model serializer. To use, instantiate and
# call #serialize
class OptimizedProjectSerializer
  PROJECT_ATTRIBUTES = %w[
    dependent_repos_count
    dependents_count
    deprecation_reason
    description
    homepage
    keywords
    language
    latest_release_number
    latest_release_published_at
    latest_stable_release_number
    latest_stable_release_published_at
    license_normalized
    license_set_by_admin
    licenses
    normalized_licenses
    platform
    rank
    repository_url
    score
    status
  ].freeze

  VERSION_ATTRIBUTES = %w[
    number
    published_at
    spdx_expression
    original_license
    researched_at
    repository_sources
  ].freeze

  MAINTENANCE_STAT_ATTRIBUTES = %w[
    category
    value
    updated_at
  ].freeze

  def initialize(projects, requested_name_map, internal_key = false)
    @projects = projects
    @requested_name_map = requested_name_map
    @internal_key = internal_key
  end

  def serialize
    Google::Cloud::Trace.in_span "optimized_project_serializer#serialize" do |_span|
      @projects.map do |project|
        serialize_project(project)
      end
    end
  end

  def serialize_project(project)
    Google::Cloud::Trace.in_span "optimized_project_serializer#serialize_project" do |_span|
      project
        .attributes
        .slice(*PROJECT_ATTRIBUTES)
        .merge!(
          canonical_name: project.name,
          name: @requested_name_map[[project.platform, project.name]],
          download_url: project.download_url,
          forks: project.forks,
          latest_download_url: project.latest_download_url,
          package_manager_url: project.package_manager_url,
          repository_license: project.repository_license,
          stars: project.stars,
          versions: versions[project.id]
        ).tap do |result|
          if @internal_key
            result[:updated_at] = project.updated_at
            result[:repository_maintenance_stats] = maintenance_stats[project.repository_id]
          end
        end
    end
  end

  def versions
    @versions ||= Google::Cloud::Trace.in_span "optimized_project_serializer#versions" do |_span|
      Version
        .where(project_id: @projects.map(&:id))
        .pluck(*VERSION_ATTRIBUTES, :created_at, :project_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, versions|
          # Use created_at if no published date
          version = VERSION_ATTRIBUTES.zip(row).to_h
          version["published_at"] ||= row[-2]

          versions[row[-1]] << version
        end
    end
  end

  def maintenance_stats
    @maintenance_stats ||= Google::Cloud::Trace.in_span "optimized_project_serializer#maintenance_stats" do |_span|
      RepositoryMaintenanceStat
        .where(repository_id: @projects.map { |p| p.repository&.id }.compact)
        .pluck(*MAINTENANCE_STAT_ATTRIBUTES, :repository_id)
        .each_with_object(Hash.new { |h, k| h[k] = [] }) do |row, stats|
          stats[row[-1]] << MAINTENANCE_STAT_ATTRIBUTES.zip(row).to_h
        end
    end
  end
end

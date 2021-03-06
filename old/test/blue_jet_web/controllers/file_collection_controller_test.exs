defmodule BlueJetWeb.FileCollectionControllerTest do
  use BlueJetWeb.ConnCase

  alias BlueJet.Identity.User

  alias BlueJet.FileStorage.FileCollection
  alias BlueJet.FileStorage.FileCollectionMembership
  alias BlueJet.FileStorage.File
  alias BlueJet.Inventory.Sku
  alias BlueJet.Repo

  @valid_attrs %{
    "label" => "primary_images"
  }
  @invalid_attrs %{
    "label" => ""
  }

  setup do
    {_, %User{ default_account_id: account1_id }} = Identity.create_user(%{
      fields: %{
        "first_name" => Faker.Name.first_name(),
        "last_name" => Faker.Name.last_name(),
        "email" => "test1@example.com",
        "password" => "test1234",
        "account_name" => Faker.Company.name()
      }
    })
    {:ok, %{ access_token: uat1 }} = Identity.authenticate(%{ username: "test1@example.com", password: "test1234", scope: "type:user" })

    conn = build_conn()
      |> put_req_header("accept", "application/vnd.api+json")
      |> put_req_header("content-type", "application/vnd.api+json")

    %{ conn: conn, uat1: uat1, account1_id: account1_id }
  end

  describe "POST /v1/file_collections" do
    test "with no access token", %{ conn: conn } do
      conn = post(conn, "/v1/file_collections", %{
        "data" => %{
          "type" => "FileCollection",
          "attributes" => @valid_attrs
        }
      })

      assert conn.status == 401
    end

    test "with invalid attrs and rels", %{ conn: conn, uat1: uat1 } do
      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = post(conn, "/v1/file_collections", %{
        "data" => %{
          "type" => "FileCollection",
          "attributes" => @invalid_attrs
        }
      })

      assert json_response(conn, 422)["errors"]
      assert length(json_response(conn, 422)["errors"]) > 0
    end

    test "with valid attrs and rels", %{ conn: conn, uat1: uat1 } do
      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = post(conn, "/v1/file_collections", %{
        "data" => %{
          "type" => "FileCollection",
          "attributes" => @valid_attrs
        }
      })

      assert json_response(conn, 201)["data"]["id"]
      assert json_response(conn, 201)["data"]["attributes"]["label"] == @valid_attrs["label"]
    end

    test "with valid attrs, rels and include", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      %Sku{ id: sku_id } = Repo.insert!(%Sku{
        account_id: account1_id,
        status: "active",
        name: "Orange",
        print_name: "ORANGE",
        unit_of_measure: "EA",
        custom_data: %{
          "kind" => "Blue Jay"
        }
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = post(conn, "/v1/file_collections?include=sku", %{
        "data" => %{
          "type" => "FileCollection",
          "attributes" => @valid_attrs,
          "relationships" => %{
            "sku" => %{
              "data" => %{
                "type" => "Sku",
                "id" => sku_id
              }
            }
          }
        }
      })

      assert json_response(conn, 201)["data"]["id"]
      assert json_response(conn, 201)["data"]["attributes"]["label"] == @valid_attrs["label"]
      assert json_response(conn, 201)["data"]["relationships"]["sku"]["data"]["id"]
      assert length(Enum.filter(json_response(conn, 201)["included"], fn(item) -> item["type"] == "Sku" end)) == 1
    end
  end

  describe "GET /v1/file_collections/:id" do
    test "with no access token", %{ conn: conn } do
      conn = get(conn, "/v1/file_collections/test")

      assert conn.status == 401
    end

    test "with access token of a different account", %{ conn: conn, uat1: uat1 } do
      {:ok, %User{ default_account_id: account2_id }} = Identity.create_user(%{
        fields: %{
          "first_name" => Faker.Name.first_name(),
          "last_name" => Faker.Name.last_name(),
          "email" => "test2@example.com",
          "password" => "test1234",
          "account_name" => Faker.Company.name()
        }
      })

      efc = Repo.insert!(%FileCollection{
        account_id: account2_id,
        label: "primary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      assert_error_sent(404, fn ->
        get(conn, "/v1/file_collections/#{efc.id}")
      end)
    end

    test "with valid access token and id", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "primary_images",
        custom_data: %{
          "cd1" => "Custom Content"
        }
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections/#{efc.id}")

      assert json_response(conn, 200)["data"]["id"] == efc.id
      assert json_response(conn, 200)["data"]["attributes"]["label"] == "primary_images"
      assert json_response(conn, 200)["data"]["attributes"]["customData"]["cd1"] == "Custom Content"
    end

    test "with valid access token, id and locale", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "primary_images",
        custom_data: %{
          "cd1" => "Custom Content"
        },
        translations: %{
          "zh-CN" => %{
            "name" => "主要图片"
          }
        }
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections/#{efc.id}?locale=zh-CN")

      assert json_response(conn, 200)["data"]["id"] == efc.id
      assert json_response(conn, 200)["data"]["attributes"]["name"] == "主要图片"
      assert json_response(conn, 200)["data"]["attributes"]["label"] == "primary_images"
      assert json_response(conn, 200)["data"]["attributes"]["customData"]["cd1"] == "Custom Content"
    end

    test "with valid access token, id, locale and include", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      %File{ id: file1_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %File{ id: file2_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %Sku{ id: sku_id } = Repo.insert!(%Sku{
        account_id: account1_id,
        status: "active",
        name: "Orange",
        print_name: "ORANGE",
        unit_of_measure: "EA",
        custom_data: %{
          "kind" => "Blue Jay"
        },
        translations: %{
          "zh-CN" => %{
            "name" => "橙子"
          }
        }
      })

      efc = Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        sku_id: sku_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc.id,
        file_id: file1_id
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc.id,
        file_id: file2_id
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections/#{efc.id}?include=sku,files&locale=zh-CN")

      assert json_response(conn, 200)["data"]["id"] == efc.id
      assert json_response(conn, 200)["data"]["attributes"]["label"] == "primary_images"
      assert json_response(conn, 200)["data"]["relationships"]["sku"]["data"]["id"]
      assert length(json_response(conn, 200)["data"]["relationships"]["files"]["data"]) == 2
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "Sku" end)) == 1
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "File" end)) == 2
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["attributes"]["name"] == "橙子" end)) == 1
    end
  end

  describe "PATCH /v1/file_collections/:id" do
    test "with no access token", %{ conn: conn } do
      conn = patch(conn, "/v1/file_collections/test", %{
        "data" => %{
          "id" => "test",
          "type" => "FileCollection",
          "attributes" => @valid_attrs
        }
      })

      assert conn.status == 401
    end

    test "with access token of a different account", %{ conn: conn, uat1: uat1 } do
      {:ok, %User{ default_account_id: account2_id }} = Identity.create_user(%{
        fields: %{
          "first_name" => Faker.Name.first_name(),
          "last_name" => Faker.Name.last_name(),
          "email" => "test2@example.com",
          "password" => "test1234",
          "account_name" => Faker.Company.name()
        }
      })

      efc = Repo.insert!(%FileCollection{
        account_id: account2_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      assert_error_sent(404, fn ->
        patch(conn, "/v1/file_collections/#{efc.id}", %{
          "data" => %{
            "id" => efc.id,
            "type" => "FileCollection",
            "attributes" => @valid_attrs
          }
        })
      end)
    end

    test "with valid access token, invalid attrs and rels", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "primary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = patch(conn, "/v1/file_collections/#{efc.id}", %{
        "data" => %{
          "id" => efc.id,
          "type" => "FileCollection",
          "attributes" => @invalid_attrs
        }
      })

      assert json_response(conn, 422)["errors"]
      assert length(json_response(conn, 422)["errors"]) > 0
    end

    test "with valid access token, attrs and rels", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = patch(conn, "/v1/file_collections/#{efc.id}", %{
        "data" => %{
          "id" => efc.id,
          "type" => "FileCollection",
          "attributes" => @valid_attrs
        }
      })

      assert json_response(conn, 200)["data"]["id"]
      assert json_response(conn, 200)["data"]["attributes"]["label"] == @valid_attrs["label"]
    end

    test "with valid access token, valid attrs and locale", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        name: "Primary Images",
        account_id: account1_id,
        label: "primary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = patch(conn, "/v1/file_collections/#{efc.id}?locale=zh-CN", %{
        "data" => %{
          "id" => efc.id,
          "type" => "FileCollection",
          "attributes" => %{
            "name" => "主要图片"
          }
        }
      })

      assert json_response(conn, 200)["data"]["id"] == efc.id
      assert json_response(conn, 200)["data"]["attributes"]["name"] == "主要图片"
    end

    test "with good access token, valid attrs, rels, locale and include", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      %File{ id: file1_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %File{ id: file2_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %Sku{ id: sku_id } = Repo.insert!(%Sku{
        account_id: account1_id,
        status: "active",
        name: "Orange",
        print_name: "ORANGE",
        unit_of_measure: "EA",
        custom_data: %{
          "kind" => "Blue Jay"
        },
        translations: %{
          "zh-CN" => %{
            "name" => "橙子"
          }
        }
      })

      efc = Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        sku_id: sku_id,
        label: "secondary_images"
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc.id,
        file_id: file1_id
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc.id,
        file_id: file2_id
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = patch(conn, "/v1/file_collections/#{efc.id}?include=sku,files&locale=zh-CN", %{
        "data" => %{
          "id" => efc.id,
          "type" => "FileCollection",
          "attributes" => %{
            label: "primary_images"
          }
        }
      })

      assert json_response(conn, 200)["data"]["id"] == efc.id
      assert json_response(conn, 200)["data"]["attributes"]["label"] == "primary_images"
      assert json_response(conn, 200)["data"]["relationships"]["sku"]["data"]["id"]
      assert length(json_response(conn, 200)["data"]["relationships"]["files"]["data"]) == 2
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "Sku" end)) == 1
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "File" end)) == 2
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["attributes"]["name"] == "橙子" end)) == 1
    end
  end

  describe "GET /v1/file_collections" do
    test "with no access token", %{ conn: conn } do
      conn = get(conn, "/v1/file_collections")

      assert conn.status == 401
    end

    test "with valid access token", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      {:ok, %User{ default_account_id: account2_id }} = Identity.create_user(%{
        fields: %{
          "first_name" => Faker.Name.first_name(),
          "last_name" => Faker.Name.last_name(),
          "email" => "test2@example.com",
          "password" => "test1234",
          "account_name" => Faker.Company.name()
        }
      })

      Repo.insert!(%FileCollection{
        account_id: account2_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections")

      assert length(json_response(conn, 200)["data"]) == 2
    end

    test "with valid access token and pagination", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections?page[number]=2&page[size]=1")

      assert length(json_response(conn, 200)["data"]) == 1
      assert json_response(conn, 200)["meta"]["resultCount"] == 3
      assert json_response(conn, 200)["meta"]["totalCount"] == 3
    end

    test "with good access token and filter", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      Repo.insert!(%FileCollection{
        name: "Primary Images",
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        name: "primary images",
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        name: "seconary images",
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections?filter[label]=primary_images")

      assert length(json_response(conn, 200)["data"]) == 2
      assert json_response(conn, 200)["meta"]["resultCount"] == 2
      assert json_response(conn, 200)["meta"]["totalCount"] == 3
    end

    test "with valid access token and locale", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "primary_images",
        translations: %{
          "zh-CN" => %{
            "name" => "主要图片"
          }
        }
      })
      Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections?locale=zh-CN")

      assert length(json_response(conn, 200)["data"]) == 3
      assert json_response(conn, 200)["meta"]["resultCount"] == 3
      assert json_response(conn, 200)["meta"]["totalCount"] == 3
      assert length(Enum.filter(json_response(conn, 200)["data"], fn(item) -> item["attributes"]["name"] == "主要图片" end)) == 1
    end

    test "with valid access token, locale and search", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      Repo.insert!(%FileCollection{
        name: "Primary Images",
        account_id: account1_id,
        label: "primary_images",
        translations: %{
          "zh-CN" => %{
            "name" => "主要图片"
          }
        }
      })
      Repo.insert!(%FileCollection{
        name: "primary images",
        account_id: account1_id,
        label: "primary_images",
        translations: %{
          "zh-CN" => %{
            "name" => "主要图片"
          }
        }
      })
      Repo.insert!(%FileCollection{
        name: "seconary images",
        account_id: account1_id,
        label: "secondary_images",
        translations: %{
          "zh-CN" => %{
            "name" => "次要图片"
          }
        }
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections?search=主要&locale=zh-CN")

      assert length(json_response(conn, 200)["data"]) == 2
      assert json_response(conn, 200)["meta"]["resultCount"] == 2
      assert json_response(conn, 200)["meta"]["totalCount"] == 3
    end

    test "with good access token, locale and include", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      %File{ id: file1_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %File{ id: file2_id } = Repo.insert!(%File{
        account_id: account1_id,
        name: Faker.Lorem.word(),
        status: "uploaded",
        content_type: "image/png",
        size_bytes: 42
      })
      %Sku{ id: sku_id } = Repo.insert!(%Sku{
        account_id: account1_id,
        status: "active",
        name: "Orange",
        print_name: "ORANGE",
        unit_of_measure: "EA",
        custom_data: %{
          "kind" => "Blue Jay"
        },
        translations: %{
          "zh-CN" => %{
            "name" => "橙子"
          }
        }
      })
      %FileCollection{ id: efc_id } = Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        sku_id: sku_id,
        label: "secondary_images"
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc_id,
        file_id: file1_id
      })
      Repo.insert!(%FileCollectionMembership{
        account_id: account1_id,
        collection_id: efc_id,
        file_id: file2_id
      })

      Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "primary_images"
      })
      Repo.insert!(%FileCollection{
        name: "Primary Image",
        account_id: account1_id,
        label: "primary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = get(conn, "/v1/file_collections?include=sku,files&locale=zh-CN")

      assert length(json_response(conn, 200)["data"]) == 3
      assert json_response(conn, 200)["meta"]["resultCount"] == 3
      assert json_response(conn, 200)["meta"]["totalCount"] == 3
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "Sku" end)) == 1
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["type"] == "File" end)) == 2
      assert length(Enum.filter(json_response(conn, 200)["included"], fn(item) -> item["attributes"]["name"] == "橙子" end)) == 1
    end
  end

  describe "DELETE /v1/file_collections/:id" do
    test "with no access token", %{ conn: conn } do
      conn = delete(conn, "/v1/file_collections/test")

      assert conn.status == 401
    end

    test "with access token of a different account", %{ conn: conn, uat1: uat1 } do
      {:ok, %User{ default_account_id: account2_id }} = Identity.create_user(%{
        fields: %{
          "first_name" => Faker.Name.first_name(),
          "last_name" => Faker.Name.last_name(),
          "email" => "test2@example.com",
          "password" => "test1234",
          "account_name" => Faker.Company.name()
        }
      })

      efc = Repo.insert!(%FileCollection{
        account_id: account2_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      assert_error_sent(404, fn ->
        delete(conn, "/v1/file_collections/#{efc.id}")
      end)
    end

    test "with valid access token and id", %{ conn: conn, uat1: uat1, account1_id: account1_id } do
      efc = Repo.insert!(%FileCollection{
        account_id: account1_id,
        label: "secondary_images"
      })

      conn = put_req_header(conn, "authorization", "Bearer #{uat1}")

      conn = delete(conn, "/v1/file_collections/#{efc.id}")

      assert conn.status == 204
    end
  end
end

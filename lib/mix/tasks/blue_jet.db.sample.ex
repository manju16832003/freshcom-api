defmodule Mix.Tasks.BlueJet.Db.Sample do
  use Mix.Task
  import Mix.Ecto

  @shortdoc "Add sample data to db"

  @moduledoc """
    This is where we would put any long form documentation or doctests.
  """

  def run(args) do
    Mix.Tasks.Ecto.Drop.run(args)
    Mix.Tasks.Ecto.Create.run(args)
    Mix.Tasks.Ecto.Migrate.run(args)

    alias BlueJet.Repo
    alias BlueJet.Inventory.Sku
    alias BlueJet.Storefront.Product
    alias BlueJet.Storefront.ProductItem
    alias BlueJet.Storefront.Price
    alias BlueJet.Identity

    ensure_started(Repo, [])

    {:ok, %{ default_account_id: account1_id }} = Identity.create_user(%{
      fields: %{
        "first_name" => "Roy",
        "last_name" => "Bao",
        "email" => "user1@example.com",
        "password" => "test1234",
        "account_name" => "Outersky"
      }
    })
    {:ok, _} = Identity.create_customer(%{
      vas: %{ account_id: account1_id },
      fields: %{
        "first_name" => "Tiffany",
        "last_name" => "Wang",
        "email" => "customer1@example.com",
        "password" => "test1234"
      }
    })

    ########################
    # 李锦记熊猫蚝油
    ########################
    changeset = Sku.changeset(%Sku{}, %{
      "account_id" => account1_id,
      "code" => "100504",
      "status" => "active",
      "name" => "Oyster Flavoured Sauce",
      "print_name" => "OYSTER FLAVOURED SAUCE",
      "unit_of_measure" => "bottle",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "510g per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light."
    }, "en")
    sku_oyster_sauce = Repo.insert!(changeset)

    changeset = Sku.changeset(sku_oyster_sauce, %{
      "name" => "李锦记熊猫蚝油",
      "specification" => "每瓶510克。",
      "storage_description" => "常温保存，避免爆嗮。"
    }, "zh-CN")
    Repo.update!(changeset)

    ########################
    # 老干妈豆豉辣椒油
    ########################
    changeset = Sku.changeset(%Sku{}, %{
      "account_id" => account1_id,
      "code" => "100502",
      "status" => "active",
      "name" => "Chili Oil with Black Bean",
      "print_name" => "CHILI OIL BLACK BEAN",
      "unit_of_measure" => "bottle",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "280g per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light. After open keep refrigerated."
    }, "en")
    sku_chili_oil = Repo.insert!(changeset)

    changeset = Sku.changeset(sku_chili_oil, %{
      "name" => "老干妈豆豉辣椒油",
      "specification" => "每瓶280克。",
      "storage_description" => "常温保存，避免爆嗮，开启后冷藏。"
    }, "zh-CN")
    Repo.update!(changeset)

    ########################
    # 李锦记蒸鱼豉油
    ########################
    changeset = Sku.changeset(%Sku{}, %{
      "account_id" => account1_id,
      "code" => "100503",
      "status" => "active",
      "name" => "Seasoned Soy Sauce",
      "print_name" => "SEASONED SOY SAUCE",
      "unit_of_measure" => "bottle",
      "stackable" => false,
      "storage_type" => "room",
      "specification" => "410ml per bottle",
      "storage_description" => "Store in room temperature, avoid direct sun light."
    }, "en")
    sku_seasoned_soy_sauce = Repo.insert!(changeset)

    changeset = Sku.changeset(sku_seasoned_soy_sauce, %{
      "name" => "李锦记蒸鱼豉油",
      "specification" => "每瓶410毫升。",
      "storage_description" => "常温保存，避免爆嗮。"
    }, "zh-CN")
    Repo.update!(changeset)

    #######
    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "status" => "draft",
      "name" => "Seasoned Soy Sauce"
    })
    product = Repo.insert!(changeset)

    changeset = ProductItem.changeset(%ProductItem{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "sku_id" => sku_seasoned_soy_sauce.id,
      "name_sync" => "sync_with_source",
      "primary" => true
    })
    product_item = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_item_id" => product_item.id,
      "status" => "active",
      "label" => "regular",
      "charge_cents" => 599,
      "charge_unit" => "EA"
    })
    price = Repo.insert!(changeset)

    changeset = ProductItem.changeset(product_item, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)
    ######


    #######
    changeset = Product.changeset(%Product{}, %{
      "account_id" => account1_id,
      "status" => "draft",
      "item_mode" => "all",
      "name" => "Sauce Combo"
    })
    product = Repo.insert!(changeset)

    changeset = ProductItem.changeset(%ProductItem{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "sku_id" => sku_oyster_sauce.id,
      "status" => "active",
      "name_sync" => "sync_with_source"
    })
    pi_oyster_sauce = Repo.insert!(changeset)

    changeset = ProductItem.changeset(%ProductItem{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "sku_id" => sku_chili_oil.id,
      "status" => "active",
      "name_sync" => "sync_with_source"
    })
    pi_chili_oil = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_id" => product.id,
      "status" => "active",
      "label" => "regular",
      "charge_cents" => 1100,
      "charge_unit" => "EA"
    })
    price = Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_item_id" => pi_oyster_sauce.id,
      "parent_id" => price.id,
      "label" => "regular",
      "charge_cents" => 500
    })
    Repo.insert!(changeset)

    changeset = Price.changeset(%Price{}, %{
      "account_id" => account1_id,
      "product_item_id" => pi_chili_oil.id,
      "parent_id" => price.id,
      "label" => "regular",
      "charge_cents" => 600
    })
    Repo.insert!(changeset)

    changeset = ProductItem.changeset(pi_oyster_sauce, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = ProductItem.changeset(pi_chili_oil, %{
      "status" => "active"
    })
    Repo.update!(changeset)

    changeset = Product.changeset(product, %{
      "status" => "active"
    })
    Repo.update!(changeset)
    ######
  end

  # We can define other functions as needed here.
end
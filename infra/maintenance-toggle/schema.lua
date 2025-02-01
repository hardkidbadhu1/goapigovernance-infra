return {
    name = "maintenance-toggle",
    fields = {
      { config = {
          type = "record",
          fields = {
            { enabled = { type = "boolean", default = false }, },
          },
        },
      },
    },
  }
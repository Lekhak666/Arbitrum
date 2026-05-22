import axios from "axios";

export async function getPrice() {
  const res = await axios.get(
    "https://api.coinbase.com/v2/prices/ETH-USD/spot",
  );

  return parseFloat(res.data.data.amount);
}

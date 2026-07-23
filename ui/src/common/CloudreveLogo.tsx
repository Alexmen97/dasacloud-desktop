import { Box } from "@mui/material";
import { useTheme } from "@mui/material/styles";
import logoDark from "../assets/dasacloud-logo-dark.png";
import logoLight from "../assets/dasacloud-logo-light.png";

interface CloudreveLogoProps {
  height?: number;
}

export default function CloudreveLogo({ height = 28 }: CloudreveLogoProps) {
  const theme = useTheme();
  const logo = theme.palette.mode === "dark" ? logoLight : logoDark;

  return (
    <Box
      component="img"
      src={logo}
      alt="DasaCloud"
      sx={{ height }}
    />
  );
}
